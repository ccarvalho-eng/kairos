import gleam/list
import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import kairos/job
import kairos/postgres/job_store
import kairos/postgres/test_db

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn fetch_available_respects_schedule_and_priority_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let later = timestamp.add(now, duration.minutes(5))

    let assert Ok(_) =
      job_store.insert(
        connection,
        job_store.JobInsert(
          worker_name: "ImmediateWorker",
          payload: "{}",
          state: job.Pending,
          queue_name: "default",
          priority: 1,
          attempt: 0,
          max_attempts: 3,
          unique_key: None,
          errors: [],
          scheduled_at: now,
          attempted_at: None,
          completed_at: None,
          discarded_at: None,
          cancelled_at: None,
        ),
      )

    let assert Ok(_) =
      job_store.insert(
        connection,
        job_store.JobInsert(
          worker_name: "ScheduledWorker",
          payload: "{}",
          state: job.Scheduled,
          queue_name: "default",
          priority: 5,
          attempt: 0,
          max_attempts: 3,
          unique_key: None,
          errors: [],
          scheduled_at: later,
          attempted_at: None,
          completed_at: None,
          discarded_at: None,
          cancelled_at: None,
        ),
      )

    let assert Ok(available_now) =
      job_store.fetch_available(connection, now, 10)
    assert list.length(available_now) == 1

    let assert [first] = available_now
    let job_store.PersistedJob(worker_name: first_name, ..) = first
    assert first_name == "ImmediateWorker"

    let assert Ok(available_later) =
      job_store.fetch_available(
        connection,
        timestamp.add(later, duration.seconds(1)),
        10,
      )

    assert list.length(available_later) == 2

    let assert [scheduled_first, immediate_second] = available_later
    let job_store.PersistedJob(worker_name: scheduled_name, ..) =
      scheduled_first
    let job_store.PersistedJob(worker_name: immediate_name, ..) =
      immediate_second

    assert scheduled_name == "ScheduledWorker"
    assert immediate_name == "ImmediateWorker"
  })
}

pub fn retryable_and_terminal_state_round_trip_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()

    let assert Ok(retryable) =
      job_store.insert(
        connection,
        job_store.JobInsert(
          worker_name: "RetryableWorker",
          payload: "{}",
          state: job.Retryable,
          queue_name: "default",
          priority: 2,
          attempt: 2,
          max_attempts: 5,
          unique_key: None,
          errors: ["timeout", "database busy"],
          scheduled_at: now,
          attempted_at: Some(now),
          completed_at: None,
          discarded_at: None,
          cancelled_at: None,
        ),
      )

    let job_store.PersistedJob(id: retryable_id, errors: retryable_errors, ..) =
      retryable
    assert retryable_errors == ["timeout", "database busy"]

    let assert Ok(available) = job_store.fetch_available(connection, now, 10)
    let retryable_names =
      available
      |> list.map(fn(job) {
        let job_store.PersistedJob(worker_name: worker_name, ..) = job
        worker_name
      })

    assert list.contains(retryable_names, "RetryableWorker")

    let assert Ok(completed) =
      job_store.insert(
        connection,
        job_store.JobInsert(
          worker_name: "CompletedWorker",
          payload: "{}",
          state: job.Completed,
          queue_name: "default",
          priority: 0,
          attempt: 1,
          max_attempts: 1,
          unique_key: None,
          errors: [],
          scheduled_at: now,
          attempted_at: Some(now),
          completed_at: Some(now),
          discarded_at: None,
          cancelled_at: None,
        ),
      )

    let assert Ok(discarded) =
      job_store.insert(
        connection,
        job_store.JobInsert(
          worker_name: "DiscardedWorker",
          payload: "{}",
          state: job.Discarded,
          queue_name: "default",
          priority: 0,
          attempt: 5,
          max_attempts: 5,
          unique_key: None,
          errors: ["poison payload"],
          scheduled_at: now,
          attempted_at: Some(now),
          completed_at: None,
          discarded_at: Some(now),
          cancelled_at: None,
        ),
      )

    let job_store.PersistedJob(id: completed_id, completed_at: completed_at, ..) =
      completed
    let job_store.PersistedJob(
      id: discarded_id,
      discarded_at: discarded_at,
      errors: discarded_errors,
      ..,
    ) = discarded

    let expected_now = test_db.to_postgres_precision(now)

    assert completed_at == Some(expected_now)
    assert discarded_at == Some(expected_now)
    assert discarded_errors == ["poison payload"]

    let assert Ok(_) =
      job_store.insert(
        connection,
        job_store.JobInsert(
          worker_name: "ExhaustedRetryableWorker",
          payload: "{}",
          state: job.Retryable,
          queue_name: "default",
          priority: 10,
          attempt: 5,
          max_attempts: 5,
          unique_key: None,
          errors: ["max attempts reached"],
          scheduled_at: now,
          attempted_at: Some(now),
          completed_at: None,
          discarded_at: None,
          cancelled_at: None,
        ),
      )

    let assert Ok(available_after_exhausted) =
      job_store.fetch_available(connection, now, 10)
    let available_names =
      available_after_exhausted
      |> list.map(fn(job) {
        let job_store.PersistedJob(worker_name:, ..) = job
        worker_name
      })

    assert list.contains(available_names, "RetryableWorker")
    assert !list.contains(available_names, "ExhaustedRetryableWorker")

    let assert Ok(Some(fetched_retryable)) =
      job_store.fetch(connection, retryable_id)
    let assert Ok(Some(fetched_completed)) =
      job_store.fetch(connection, completed_id)
    let assert Ok(Some(fetched_discarded)) =
      job_store.fetch(connection, discarded_id)

    let job_store.PersistedJob(state: retryable_state, ..) = fetched_retryable
    let job_store.PersistedJob(state: completed_state, ..) = fetched_completed
    let job_store.PersistedJob(state: discarded_state, ..) = fetched_discarded

    assert retryable_state == job.Retryable
    assert completed_state == job.Completed
    assert discarded_state == job.Discarded
  })
}
