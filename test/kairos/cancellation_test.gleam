import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import kairos
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

pub fn cancel_at_marks_pending_and_scheduled_jobs_cancelled_test() {
  test_db.with_database(fn(connection) {
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
    let contract = example_worker()
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let now = timestamp.system_time()
    let later = timestamp.add(now, duration.minutes(10))
    let scheduled_options =
      job.with_schedule(job.default_enqueue_options(), job.At(later))

    let assert Ok(pending) =
      kairos.enqueue(kairos_config, contract, ExampleArgs(name: "pending"))
    let assert Ok(scheduled) =
      kairos.enqueue_with(
        kairos_config,
        contract,
        ExampleArgs(name: "scheduled"),
        scheduled_options,
      )

    let job.EnqueuedJob(id: pending_id, ..) = pending
    let job.EnqueuedJob(id: scheduled_id, ..) = scheduled

    let assert Ok(Nil) = kairos.cancel_at(kairos_config, pending_id, now)
    let assert Ok(Nil) = kairos.cancel_at(kairos_config, scheduled_id, now)

    let assert Ok(Some(cancelled_pending)) =
      job_store.fetch(connection, pending_id)
    let assert Ok(Some(cancelled_scheduled)) =
      job_store.fetch(connection, scheduled_id)
    let expected_now = test_db.to_postgres_precision(now)

    assert_cancelled(cancelled_pending, expected_now, [
      "kind=cancel attempt=0 reason=cancelled before execution",
    ])
    assert_cancelled(cancelled_scheduled, expected_now, [
      "kind=cancel attempt=0 reason=cancelled before execution",
    ])
  })
}

pub fn cancel_at_rejects_already_executing_jobs_test() {
  test_db.with_database(fn(connection) {
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
    let contract = example_worker()
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let now = timestamp.system_time()

    let assert Ok(enqueued) =
      kairos.enqueue(kairos_config, contract, ExampleArgs(name: "pending"))
    let job.EnqueuedJob(id:, ..) = enqueued
    let assert Ok([_claimed]) =
      job_store.claim_available(
        connection,
        "default",
        timestamp.system_time(),
        1,
      )

    let assert Error(kairos.JobNotCancellable(job.Executing)) =
      kairos.cancel_at(kairos_config, id, now)

    Nil
  })
}

pub fn cancel_at_preserves_retry_attempt_count_for_retryable_jobs_test() {
  test_db.with_database(fn(connection) {
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
    let contract = example_worker()
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let retryable_job =
      insert_retryable_job(
        connection,
        "workers.example",
        2,
        timestamp.system_time(),
      )
    let job_store.PersistedJob(id:, ..) = retryable_job
    let cancelled_at = timestamp.system_time()

    let assert Ok(Nil) = kairos.cancel_at(kairos_config, id, cancelled_at)
    let assert Ok(Some(cancelled_job)) = job_store.fetch(connection, id)
    let expected_now = test_db.to_postgres_precision(cancelled_at)

    assert_cancelled(cancelled_job, expected_now, [
      "kind=retry attempt=1 reason=temporary failure",
      "kind=cancel attempt=2 reason=cancelled before execution",
    ])

    Nil
  })
}

fn example_worker() -> worker.Worker(ExampleArgs) {
  worker.new(
    "workers.example",
    fn(args) {
      let ExampleArgs(name:) = args
      name
    },
    fn(payload) { Ok(ExampleArgs(name: payload)) },
    fn(_args) { worker.Success },
    job.default_enqueue_options(),
  )
}

fn assert_cancelled(
  persisted_job: job_store.PersistedJob,
  expected_now: timestamp.Timestamp,
  expected_errors: List(String),
) -> Nil {
  let job_store.PersistedJob(
    state: state,
    cancelled_at: cancelled_at,
    errors: errors,
    ..,
  ) = persisted_job

  assert state == job.Cancelled
  assert cancelled_at == Some(expected_now)
  assert errors == expected_errors
}

fn insert_retryable_job(
  connection: pog.Connection,
  worker_name: String,
  attempt: Int,
  scheduled_at: timestamp.Timestamp,
) -> job_store.PersistedJob {
  let assert Ok(persisted_job) =
    job_store.insert(
      connection,
      job_store.JobInsert(
        worker_name: worker_name,
        payload: "retryable",
        state: job.Retryable,
        queue_name: "default",
        priority: 0,
        attempt: attempt,
        max_attempts: 5,
        unique_key: None,
        errors: ["kind=retry attempt=1 reason=temporary failure"],
        scheduled_at: scheduled_at,
        attempted_at: Some(scheduled_at),
        completed_at: None,
        discarded_at: None,
        cancelled_at: None,
      ),
    )

  persisted_job
}
