import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
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
import kairos/queue_dispatch
import kairos/queue_dispatcher
import kairos/supervision
import kairos/worker
import pog

type ExampleArgs {
  ExampleArgs(name: String)
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn dispatch_claims_jobs_and_starts_supervised_runners_test() {
  test_db.with_database(fn(connection) {
    let contract = success_worker()
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 2, poll_interval_ms: 60_000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)

    let args = ExampleArgs(name: "kairos")
    let assert Ok(enqueued) = kairos.enqueue(kairos_config, contract, args)
    let job.EnqueuedJob(id: id, ..) = enqueued
    let now = timestamp.system_time()

    let assert Ok(started_runner_pids) =
      queue_dispatcher.dispatch(kairos_config, default_queue, started.data, now)

    let assert [_runner_pid] = started_runner_pids
    let stored = wait_for_job(connection, id, 20)
    let job_store.PersistedJob(state: state, completed_at: completed_at, ..) =
      stored

    assert state == job.Completed
    assert completed_at == Some(test_db.to_postgres_precision(now))

    let assert Ok(runner_supervisor_pid) =
      supervision.queue_runner_supervisor_pid(started.data, "default")
    assert process.is_alive(runner_supervisor_pid)

    stop_process(started.pid)
  })
}

pub fn dispatch_persists_retry_discard_and_cancel_outcomes_test() {
  test_db.with_database(fn(connection) {
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 3, poll_interval_ms: 60_000)
    let retry_worker =
      result_worker("workers.retry", worker.Retry("retry later"))
    let discard_worker =
      result_worker("workers.discard", worker.Discard("discard permanently"))
    let cancel_worker =
      result_worker("workers.cancel", worker.Cancel("cancel execution"))
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(retry_worker),
        worker.register(discard_worker),
        worker.register(cancel_worker),
      ])
    let assert Ok(started) = kairos.start(kairos_config)

    let assert Ok(retried) =
      kairos.enqueue(kairos_config, retry_worker, ExampleArgs(name: "retry"))
    let assert Ok(discarded) =
      kairos.enqueue(
        kairos_config,
        discard_worker,
        ExampleArgs(name: "discard"),
      )
    let assert Ok(cancelled) =
      kairos.enqueue(kairos_config, cancel_worker, ExampleArgs(name: "cancel"))
    let now = timestamp.system_time()

    let assert Ok(started_runner_pids) =
      queue_dispatcher.dispatch(kairos_config, default_queue, started.data, now)
    assert list.length(started_runner_pids) == 3

    let job.EnqueuedJob(id: retried_id, ..) = retried
    let job.EnqueuedJob(id: discarded_id, ..) = discarded
    let job.EnqueuedJob(id: cancelled_id, ..) = cancelled

    let stored_retried = wait_for_job(connection, retried_id, 20)
    let stored_discarded = wait_for_job(connection, discarded_id, 20)
    let stored_cancelled = wait_for_job(connection, cancelled_id, 20)

    let expected_retry_at =
      job_runner.retry_scheduled_at(
        kairos_config,
        stored_retried,
        now,
        "kind=retry attempt=1 reason=retry later",
      )
      |> test_db.to_postgres_precision
    let expected_now = test_db.to_postgres_precision(now)

    assert_retryable(
      stored_retried,
      expected_retry_at,
      "kind=retry",
      "retry later",
    )
    assert_discarded(stored_discarded, expected_now, "discard permanently")
    assert_cancelled(stored_cancelled, expected_now, "cancel execution")

    stop_process(started.pid)
  })
}

pub fn dispatch_returns_claim_failed_for_invalid_connection_test() {
  test_db.with_database(fn(connection) {
    let contract = success_worker()
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 1, poll_interval_ms: 60_000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)
    let assert Ok(_) =
      pog.query("DROP TABLE kairos_jobs") |> pog.execute(connection)

    let assert Error(queue_dispatcher.ClaimFailed(job_store.QueryFailed(_))) =
      queue_dispatcher.dispatch(
        kairos_config,
        default_queue,
        started.data,
        timestamp.system_time(),
      )

    stop_process(started.pid)
  })
}

pub fn dispatch_releases_claimed_jobs_when_runner_supervisor_is_unavailable_test() {
  test_db.with_database(fn(connection) {
    let contract = success_worker()
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 1, poll_interval_ms: 60_000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(enqueued) =
      kairos.enqueue(kairos_config, contract, ExampleArgs(name: "retry"))
    let job.EnqueuedJob(id:, ..) = enqueued
    let now = timestamp.system_time()
    let assert Ok([claimed_job]) =
      job_store.claim_available(connection, "default", now, 1)

    let assert Error(queue_dispatch.QueueRuntimeUnavailable("default", _)) =
      queue_dispatch.dispatch_claimed(
        kairos_config,
        "default",
        process.new_name("missing-runner-supervisor"),
        [claimed_job],
        now,
      )
    let stored = wait_for_job(connection, id, 20)
    let job_store.PersistedJob(state:, attempt:, errors:, ..) = stored

    assert state == job.Retryable
    assert attempt == 1
    let assert [error] = errors
    assert string.contains(error, "kind=runner_start")
  })
}

fn success_worker() -> worker.Worker(ExampleArgs) {
  result_worker("workers.success", worker.Success)
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

fn wait_for_job(
  connection: pog.Connection,
  id: String,
  remaining_attempts: Int,
) -> job_store.PersistedJob {
  let assert Ok(Some(stored)) = job_store.fetch(connection, id)
  let job_store.PersistedJob(state:, ..) = stored

  case state, remaining_attempts {
    job.Completed, _ -> stored
    job.Retryable, _ -> stored
    job.Discarded, _ -> stored
    job.Cancelled, _ -> stored
    _, 0 -> panic as "timed out waiting for terminal job state"
    _, _ -> {
      process.sleep(25)
      wait_for_job(connection, id, remaining_attempts - 1)
    }
  }
}

fn assert_retryable(
  persisted_job: job_store.PersistedJob,
  expected_scheduled_at: timestamp.Timestamp,
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
  assert scheduled_at == expected_scheduled_at
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

fn stop_process(pid: process.Pid) -> Nil {
  process.unlink(pid)
  process.send_abnormal_exit(pid, "test shutdown")
  process.sleep(25)
}
