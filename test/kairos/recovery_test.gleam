import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import kairos
import kairos/backoff
import kairos/config
import kairos/job
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

pub fn recover_stale_retries_and_discards_stale_executing_jobs_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let stale_attempted_at = timestamp.add(now, duration.minutes(-10))
    let retry_contract =
      worker.with_backoff(
        result_worker("workers.retry", worker.Success),
        backoff.constant_policy(90),
      )
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(retry_contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)

    let retryable_job =
      insert_executing_job(
        connection,
        worker_name: "workers.retry",
        attempt: 1,
        max_attempts: 3,
        attempted_at: stale_attempted_at,
      )
    let exhausted_job =
      insert_executing_job(
        connection,
        worker_name: "workers.retry",
        attempt: 3,
        max_attempts: 3,
        attempted_at: stale_attempted_at,
      )

    let assert Ok(2) =
      kairos.recover_stale(started.data, "default", now, duration.minutes(5))

    let job_store.PersistedJob(id: retryable_id, ..) = retryable_job
    let job_store.PersistedJob(id: exhausted_id, ..) = exhausted_job
    let assert Ok(Some(stored_retryable)) =
      job_store.fetch(connection, retryable_id)
    let assert Ok(Some(stored_exhausted)) =
      job_store.fetch(connection, exhausted_id)

    assert_retryable(
      stored_retryable,
      test_db.to_postgres_precision(now),
      1,
      "kind=stale attempt=1 reason=stale execution recovered",
    )
    assert_discarded(
      stored_exhausted,
      test_db.to_postgres_precision(now),
      1,
      "kind=stale attempt=3 reason=stale execution recovered",
    )

    process.send_exit(started.pid)
  })
}

pub fn recover_stale_restores_abandoned_jobs_after_restart_test() {
  test_db.with_database(fn(connection) {
    let claim_now =
      timestamp.add(timestamp.system_time(), duration.minutes(-10))
    let recover_now = timestamp.system_time()
    let contract = result_worker("workers.restart", worker.Success)
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(first_runtime) = kairos.start(kairos_config)
    let scheduled_options =
      job.with_schedule(job.default_enqueue_options(), job.At(claim_now))
    let assert Ok(enqueued) =
      kairos.enqueue_with(
        kairos_config,
        contract,
        ExampleArgs(name: "restart"),
        scheduled_options,
      )
    let job.EnqueuedJob(id:, ..) = enqueued

    let assert Ok([_claimed]) =
      job_store.claim_available(connection, "default", claim_now, 1)
    process.send_exit(first_runtime.pid)

    let assert Ok(second_runtime) = kairos.start(kairos_config)
    let assert Ok(1) =
      kairos.recover_stale(
        second_runtime.data,
        "default",
        recover_now,
        duration.minutes(5),
      )

    let assert Ok(Some(recovered_job)) = job_store.fetch(connection, id)

    assert_retryable(
      recovered_job,
      test_db.to_postgres_precision(recover_now),
      1,
      "kind=stale attempt=1 reason=stale execution recovered",
    )

    process.send_exit(second_runtime.pid)
  })
}

pub fn recover_stale_ignores_recent_executing_jobs_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let recent_attempted_at = timestamp.add(now, duration.minutes(-2))
    let contract = result_worker("workers.recent", worker.Success)
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)
    let recent_job =
      insert_executing_job(
        connection,
        worker_name: "workers.recent",
        attempt: 1,
        max_attempts: 3,
        attempted_at: recent_attempted_at,
      )

    let assert Ok(0) =
      kairos.recover_stale(started.data, "default", now, duration.minutes(5))

    let job_store.PersistedJob(id:, ..) = recent_job
    let assert Ok(Some(stored_job)) = job_store.fetch(connection, id)
    let job_store.PersistedJob(state:, attempted_at:, errors:, ..) = stored_job

    assert state == job.Executing
    assert attempted_at
      == Some(test_db.to_postgres_precision(recent_attempted_at))
    assert list.is_empty(errors)

    process.send_exit(started.pid)
  })
}

pub fn recover_stale_ignores_non_positive_stale_window_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let stale_attempted_at = timestamp.add(now, duration.minutes(-10))
    let contract = result_worker("workers.non_positive", worker.Success)
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)
    let stale_job =
      insert_executing_job(
        connection,
        worker_name: "workers.non_positive",
        attempt: 1,
        max_attempts: 3,
        attempted_at: stale_attempted_at,
      )

    let assert Ok(0) =
      kairos.recover_stale(
        started.data,
        "default",
        now,
        duration.milliseconds(0),
      )
    let assert Ok(0) =
      kairos.recover_stale(started.data, "default", now, duration.minutes(-1))

    let job_store.PersistedJob(id:, ..) = stale_job
    let assert Ok(Some(stored_job)) = job_store.fetch(connection, id)
    let job_store.PersistedJob(state:, attempted_at:, errors:, ..) = stored_job

    assert state == job.Executing
    assert attempted_at
      == Some(test_db.to_postgres_precision(stale_attempted_at))
    assert list.is_empty(errors)

    process.send_exit(started.pid)
  })
}

pub fn recover_stale_returns_error_for_unknown_queue_test() {
  test_db.with_database(fn(connection) {
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [])
    let assert Ok(started) = kairos.start(kairos_config)

    let result =
      kairos.recover_stale(
        started.data,
        "missing",
        timestamp.system_time(),
        duration.minutes(5),
      )

    assert result == Error(kairos.QueueRuntimeUnavailable("missing"))

    process.send_exit(started.pid)
  })
}

pub fn recover_stale_processes_multiple_batches_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let stale_attempted_at = timestamp.add(now, duration.minutes(-10))
    let contract = result_worker("workers.batched", worker.Success)
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)
    let stale_jobs =
      insert_executing_jobs(
        connection,
        worker_name: "workers.batched",
        count: 101,
        attempted_at: stale_attempted_at,
        jobs: [],
      )

    let assert Ok(101) =
      kairos.recover_stale(started.data, "default", now, duration.minutes(5))

    assert_jobs_recovered_retryable(
      connection,
      stale_jobs,
      test_db.to_postgres_precision(now),
    )

    process.send_exit(started.pid)
  })
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

fn insert_executing_job(
  connection: pog.Connection,
  worker_name worker_name: String,
  attempt attempt: Int,
  max_attempts max_attempts: Int,
  attempted_at attempted_at: timestamp.Timestamp,
) -> job_store.PersistedJob {
  let assert Ok(persisted_job) =
    job_store.insert(
      connection,
      job_store.JobInsert(
        worker_name: worker_name,
        payload: "kairos",
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

  persisted_job
}

fn insert_executing_jobs(
  connection connection: pog.Connection,
  worker_name worker_name: String,
  count count: Int,
  attempted_at attempted_at: timestamp.Timestamp,
  jobs jobs: List(job_store.PersistedJob),
) -> List(job_store.PersistedJob) {
  case count {
    0 -> list.reverse(jobs)
    _ ->
      insert_executing_jobs(
        connection: connection,
        worker_name: worker_name,
        count: count - 1,
        attempted_at: attempted_at,
        jobs: [
          insert_executing_job(
            connection,
            worker_name: worker_name,
            attempt: 1,
            max_attempts: 3,
            attempted_at: attempted_at,
          ),
          ..jobs
        ],
      )
  }
}

fn assert_jobs_recovered_retryable(
  connection: pog.Connection,
  jobs: List(job_store.PersistedJob),
  expected_scheduled_at: timestamp.Timestamp,
) -> Nil {
  case jobs {
    [] -> Nil
    [job_store.PersistedJob(id:, ..), ..rest] -> {
      let assert Ok(Some(stored_job)) = job_store.fetch(connection, id)
      assert_retryable(
        stored_job,
        expected_scheduled_at,
        1,
        "kind=stale attempt=1 reason=stale execution recovered",
      )
      assert_jobs_recovered_retryable(connection, rest, expected_scheduled_at)
    }
  }
}

fn assert_retryable(
  persisted_job: job_store.PersistedJob,
  expected_scheduled_at: timestamp.Timestamp,
  expected_error_count: Int,
  expected_last_error: String,
) -> Nil {
  let job_store.PersistedJob(
    state: state,
    scheduled_at: scheduled_at,
    errors: errors,
    ..,
  ) = persisted_job

  assert state == job.Retryable
  assert scheduled_at == expected_scheduled_at
  assert list.length(errors) == expected_error_count
  let assert Ok(last_error) = list.last(errors)
  assert string.contains(last_error, expected_last_error)
}

fn assert_discarded(
  persisted_job: job_store.PersistedJob,
  expected_now: timestamp.Timestamp,
  expected_error_count: Int,
  expected_last_error: String,
) -> Nil {
  let job_store.PersistedJob(
    state: state,
    discarded_at: discarded_at,
    errors: errors,
    ..,
  ) = persisted_job

  assert state == job.Discarded
  assert discarded_at == Some(expected_now)
  assert list.length(errors) == expected_error_count
  let assert Ok(last_error) = list.last(errors)
  assert string.contains(last_error, expected_last_error)
}
