import gleam/option.{None, Some}
import gleam/string
import gleam/time/timestamp
import gleeunit
import kairos
import kairos/config
import kairos/job
import kairos/job_runner
import kairos/postgres/job_store
import kairos/postgres/test_db
import kairos/queue
import kairos/worker
import pog

type ExampleArgs {
  ExampleArgs(name: String)
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn run_claimed_marks_successful_jobs_completed_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let contract = result_worker("workers.success", worker.Success)
    let kairos_config = build_config(connection, [worker.register(contract)])
    let claimed = enqueue_and_claim(kairos_config, contract, now)

    let assert Ok(finished) =
      job_runner.run_claimed(kairos_config, claimed, now)
    let expected_now = test_db.to_postgres_precision(now)

    let job_store.PersistedJob(
      id: id,
      state: state,
      completed_at: completed_at,
      errors: errors,
      ..,
    ) = finished

    assert state == job.Completed
    assert completed_at == Some(expected_now)
    assert errors == []

    let assert Ok(Some(stored)) = job_store.fetch(connection, id)
    let job_store.PersistedJob(state: stored_state, ..) = stored
    assert stored_state == job.Completed
  })
}

pub fn run_claimed_persists_retry_discard_and_cancel_outcomes_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let retry_contract =
      result_worker("workers.retry", worker.Retry("retry later"))
    let kairos_config =
      build_config(connection, [worker.register(retry_contract)])
    let retried = enqueue_and_run_claimed(kairos_config, retry_contract, now)
    let expected_now = test_db.to_postgres_precision(now)

    assert_retryable(retried, expected_now, "kind=retry", "retry later")
  })
}

pub fn run_claimed_persists_discard_outcome_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let discard_contract =
      result_worker("workers.discard", worker.Discard("discard permanently"))
    let kairos_config =
      build_config(connection, [worker.register(discard_contract)])
    let discarded =
      enqueue_and_run_claimed(kairos_config, discard_contract, now)

    let expected_now = test_db.to_postgres_precision(now)
    assert_discarded(discarded, expected_now, "discard permanently")
  })
}

pub fn run_claimed_persists_cancel_outcome_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let cancel_contract =
      result_worker("workers.cancel", worker.Cancel("cancel execution"))
    let kairos_config =
      build_config(connection, [worker.register(cancel_contract)])
    let cancelled = enqueue_and_run_claimed(kairos_config, cancel_contract, now)

    let expected_now = test_db.to_postgres_precision(now)
    assert_cancelled(cancelled, expected_now, "cancel execution")
  })
}

pub fn run_claimed_discards_decode_failures_and_missing_workers_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let decode_contract = decode_failure_worker("workers.decode")
    let kairos_config =
      build_config(connection, [worker.register(decode_contract)])

    let malformed_job =
      insert_executing_job(
        connection,
        worker_name: "workers.decode",
        payload: "bad payload",
        max_attempts: 3,
        attempt: 1,
        attempted_at: now,
      )
    let missing_worker_job =
      insert_executing_job(
        connection,
        worker_name: "workers.missing",
        payload: "kairos",
        max_attempts: 3,
        attempt: 1,
        attempted_at: now,
      )

    let decode_failed = run_claimed(kairos_config, malformed_job, now)
    let missing_worker = run_claimed(kairos_config, missing_worker_job, now)

    let expected_now = test_db.to_postgres_precision(now)

    assert_discarded(decode_failed, expected_now, "payload mismatch")
    assert_discarded(missing_worker, expected_now, "worker not configured")
  })
}

pub fn run_claimed_records_crashes_and_exhausted_retries_as_discarded_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let crashing_contract = crashing_worker("workers.crash")
    let exhausted_retry_contract =
      result_worker("workers.exhausted", worker.Retry("retry later"))
    let kairos_config =
      build_config(connection, [
        worker.register(crashing_contract),
        worker.register(exhausted_retry_contract),
      ])

    let crashing_job = enqueue_and_claim(kairos_config, crashing_contract, now)
    let exhausted_job =
      enqueue_and_claim_with_attempts(
        kairos_config,
        exhausted_retry_contract,
        1,
        now,
      )

    let crashed = run_claimed(kairos_config, crashing_job, now)
    let exhausted = run_claimed(kairos_config, exhausted_job, now)

    let expected_now = test_db.to_postgres_precision(now)

    assert_retryable(crashed, expected_now, "kind=crash", "worker crashed")
    assert_discarded(exhausted, expected_now, "retry later")
  })
}

fn build_config(
  connection: pog.Connection,
  registered_workers: List(worker.RegisteredWorker),
) -> config.Config {
  let assert Ok(default_queue) =
    queue.new(name: "default", concurrency: 10, poll_interval_ms: 1000)
  let assert Ok(kairos_config) =
    config.new(
      connection: connection,
      queues: [default_queue],
      workers: registered_workers,
    )
  kairos_config
}

fn enqueue_and_run_claimed(
  kairos_config: config.Config,
  contract: worker.Worker(ExampleArgs),
  now: timestamp.Timestamp,
) -> job_store.PersistedJob {
  let claimed = enqueue_and_claim(kairos_config, contract, now)
  run_claimed(kairos_config, claimed, now)
}

fn run_claimed(
  kairos_config: config.Config,
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
) -> job_store.PersistedJob {
  let assert Ok(finished) =
    job_runner.run_claimed(kairos_config, claimed_job, now)
  finished
}

fn enqueue_and_claim(
  kairos_config: config.Config,
  contract: worker.Worker(ExampleArgs),
  now: timestamp.Timestamp,
) -> job_store.PersistedJob {
  enqueue_and_claim_with_attempts(kairos_config, contract, 3, now)
}

fn enqueue_and_claim_with_attempts(
  kairos_config: config.Config,
  contract: worker.Worker(ExampleArgs),
  max_attempts: Int,
  _now: timestamp.Timestamp,
) -> job_store.PersistedJob {
  let args = ExampleArgs(name: worker.name(contract))
  let assert Ok(custom_options) =
    job.with_max_attempts(worker.default_options(contract), max_attempts)
  let assert Ok(_) =
    kairos.enqueue_with(kairos_config, contract, args, custom_options)
  let claim_now = timestamp.system_time()
  let assert Ok([claimed]) =
    job_store.claim_available(
      config.connection(kairos_config),
      "default",
      claim_now,
      1,
    )
  claimed
}

fn insert_executing_job(
  connection: pog.Connection,
  worker_name worker_name: String,
  payload payload: String,
  max_attempts max_attempts: Int,
  attempt attempt: Int,
  attempted_at attempted_at: timestamp.Timestamp,
) -> job_store.PersistedJob {
  let assert Ok(inserted) =
    job_store.insert(
      connection,
      job_store.JobInsert(
        worker_name: worker_name,
        payload: payload,
        state: job.Executing,
        queue_name: "default",
        priority: 0,
        attempt: attempt,
        max_attempts: max_attempts,
        unique_key: None,
        errors: [],
        scheduled_at: attempted_at,
        attempted_at: Some(attempted_at),
        completed_at: None,
        discarded_at: None,
        cancelled_at: None,
      ),
    )
  inserted
}

fn assert_retryable(
  persisted_job: job_store.PersistedJob,
  expected_now: timestamp.Timestamp,
  expected_kind: String,
  reason_substring: String,
) -> Nil {
  let job_store.PersistedJob(
    state: state,
    scheduled_at: scheduled_at,
    errors: errors,
    ..,
  ) = persisted_job

  assert state == job.Retryable
  assert scheduled_at == expected_now
  let assert [error] = errors
  assert string.contains(error, expected_kind)
  assert string.contains(error, reason_substring)
}

fn assert_discarded(
  persisted_job: job_store.PersistedJob,
  expected_now: timestamp.Timestamp,
  reason_substring: String,
) -> Nil {
  let job_store.PersistedJob(
    state: state,
    discarded_at: discarded_at,
    errors: errors,
    ..,
  ) = persisted_job

  assert state == job.Discarded
  assert discarded_at == Some(expected_now)
  let assert [error] = errors
  assert string.contains(error, reason_substring)
}

fn assert_cancelled(
  persisted_job: job_store.PersistedJob,
  expected_now: timestamp.Timestamp,
  reason_substring: String,
) -> Nil {
  let job_store.PersistedJob(
    state: state,
    cancelled_at: cancelled_at,
    errors: errors,
    ..,
  ) = persisted_job

  assert state == job.Cancelled
  assert cancelled_at == Some(expected_now)
  let assert [error] = errors
  assert string.contains(error, reason_substring)
}

fn result_worker(
  name: String,
  result: worker.PerformResult,
) -> worker.Worker(ExampleArgs) {
  worker.new(
    name,
    fn(args) {
      let ExampleArgs(name:) = args
      name
    },
    fn(payload) { Ok(ExampleArgs(name: payload)) },
    fn(_args) { result },
    job.default_enqueue_options(),
  )
}

fn decode_failure_worker(name: String) -> worker.Worker(ExampleArgs) {
  worker.new(
    name,
    fn(args) {
      let ExampleArgs(name:) = args
      name
    },
    fn(_payload) { Error(worker.DecodeError("payload mismatch")) },
    fn(_args) { worker.Success },
    job.default_enqueue_options(),
  )
}

fn crashing_worker(name: String) -> worker.Worker(ExampleArgs) {
  worker.new(
    name,
    fn(args) {
      let ExampleArgs(name:) = args
      name
    },
    fn(payload) { Ok(ExampleArgs(name: payload)) },
    fn(_args) { panic as "worker crashed" },
    job.default_enqueue_options(),
  )
}
