import gleam/list
import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import kairos/job
import kairos/postgres/job_store
import kairos/postgres/test_db
import pog

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn claim_available_claims_only_runnable_jobs_for_the_queue_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let earlier = timestamp.add(now, duration.seconds(-30))
    let later = timestamp.add(now, duration.minutes(5))

    let assert Ok(_) =
      insert_job(
        connection,
        worker_name: "RetryableWorker",
        state: job.Retryable,
        queue_name: "default",
        priority: 5,
        attempt: 1,
        max_attempts: 3,
        scheduled_at: earlier,
      )
    let assert Ok(_) =
      insert_job(
        connection,
        worker_name: "PendingWorker",
        state: job.Pending,
        queue_name: "default",
        priority: 1,
        attempt: 0,
        max_attempts: 3,
        scheduled_at: now,
      )
    let assert Ok(mailers) =
      insert_job(
        connection,
        worker_name: "MailersWorker",
        state: job.Pending,
        queue_name: "mailers",
        priority: 10,
        attempt: 0,
        max_attempts: 3,
        scheduled_at: now,
      )
    let assert Ok(scheduled) =
      insert_job(
        connection,
        worker_name: "ScheduledWorker",
        state: job.Scheduled,
        queue_name: "default",
        priority: 10,
        attempt: 0,
        max_attempts: 3,
        scheduled_at: later,
      )
    let assert Ok(exhausted) =
      insert_job(
        connection,
        worker_name: "ExhaustedWorker",
        state: job.Retryable,
        queue_name: "default",
        priority: 9,
        attempt: 3,
        max_attempts: 3,
        scheduled_at: earlier,
      )

    let assert Ok(claimed) =
      job_store.claim_available(connection, "default", now, 10)

    let assert [first, second] = claimed
    let expected_now = test_db.to_postgres_precision(now)

    assert claimed_worker_names(claimed)
      == [
        "RetryableWorker",
        "PendingWorker",
      ]

    let job_store.PersistedJob(
      id: retryable_id,
      state: retryable_state,
      attempt: retryable_attempt,
      attempted_at: retryable_attempted_at,
      ..,
    ) = first
    let job_store.PersistedJob(
      id: pending_id,
      state: pending_state,
      attempt: pending_attempt,
      attempted_at: pending_attempted_at,
      ..,
    ) = second

    assert retryable_state == job.Executing
    assert pending_state == job.Executing
    assert retryable_attempt == 2
    assert pending_attempt == 1
    assert retryable_attempted_at == Some(expected_now)
    assert pending_attempted_at == Some(expected_now)

    let job_store.PersistedJob(id: scheduled_id, ..) = scheduled
    let job_store.PersistedJob(id: exhausted_id, ..) = exhausted

    assert_job_state(connection, retryable_id, job.Executing)
    assert_job_state(connection, pending_id, job.Executing)
    assert_job_state(connection, scheduled_id, job.Scheduled)
    assert_job_state(connection, exhausted_id, job.Retryable)

    let job_store.PersistedJob(id: mailers_id, ..) = mailers
    assert_job_state(connection, mailers_id, job.Pending)
  })
}

pub fn claim_available_does_not_reclaim_already_claimed_jobs_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()

    let assert Ok(_) =
      insert_job(
        connection,
        worker_name: "FirstWorker",
        state: job.Pending,
        queue_name: "default",
        priority: 10,
        attempt: 0,
        max_attempts: 3,
        scheduled_at: now,
      )
    let assert Ok(_) =
      insert_job(
        connection,
        worker_name: "SecondWorker",
        state: job.Pending,
        queue_name: "default",
        priority: 5,
        attempt: 0,
        max_attempts: 3,
        scheduled_at: now,
      )
    let assert Ok(_) =
      insert_job(
        connection,
        worker_name: "ThirdWorker",
        state: job.Pending,
        queue_name: "default",
        priority: 1,
        attempt: 0,
        max_attempts: 3,
        scheduled_at: now,
      )

    let assert Ok(first_claim) =
      job_store.claim_available(connection, "default", now, 2)
    let assert Ok(second_claim) =
      job_store.claim_available(connection, "default", now, 2)

    assert claimed_worker_names(first_claim) == ["FirstWorker", "SecondWorker"]
    assert claimed_worker_names(second_claim) == ["ThirdWorker"]

    let claimed_ids =
      first_claim
      |> list.append(second_claim)
      |> list.map(fn(claimed_job) {
        let job_store.PersistedJob(id:, ..) = claimed_job
        id
      })

    assert list.length(claimed_ids) == 3
    assert list.unique(claimed_ids) == claimed_ids

    let assert Ok(third_claim) =
      job_store.claim_available(connection, "default", now, 2)
    assert third_claim == []
  })
}

fn insert_job(
  connection: pog.Connection,
  worker_name worker_name: String,
  state state: job.JobState,
  queue_name queue_name: String,
  priority priority: Int,
  attempt attempt: Int,
  max_attempts max_attempts: Int,
  scheduled_at scheduled_at: timestamp.Timestamp,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  let attempted_at = case attempt > 0 {
    True -> Some(scheduled_at)
    False -> None
  }

  job_store.insert(
    connection,
    job_store.JobInsert(
      worker_name: worker_name,
      payload: "{}",
      state: state,
      queue_name: queue_name,
      priority: priority,
      attempt: attempt,
      max_attempts: max_attempts,
      unique_key: None,
      errors: [],
      scheduled_at: scheduled_at,
      attempted_at: attempted_at,
      completed_at: None,
      discarded_at: None,
      cancelled_at: None,
    ),
  )
}

fn claimed_worker_names(
  claimed_jobs: List(job_store.PersistedJob),
) -> List(String) {
  claimed_jobs
  |> list.map(fn(claimed_job) {
    let job_store.PersistedJob(worker_name:, ..) = claimed_job
    worker_name
  })
}

fn assert_job_state(
  connection: pog.Connection,
  id: String,
  expected_state: job.JobState,
) -> Nil {
  let assert Ok(Some(persisted_job)) = job_store.fetch(connection, id)
  let job_store.PersistedJob(state:, ..) = persisted_job
  assert state == expected_state
}
