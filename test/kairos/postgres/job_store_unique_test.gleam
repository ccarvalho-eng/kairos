import gleam/option.{None, Some}
import gleam/time/timestamp
import gleeunit
import kairos/job
import kairos/postgres/job_store
import kairos/postgres/test_db

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn unique_key_only_blocks_active_jobs_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let unique_key = Some("daily-report")

    let assert Ok(_) =
      job_store.insert(
        connection,
        job_store.JobInsert(
          worker_name: "CancelledJobWorker",
          payload: "{}",
          state: job.Cancelled,
          queue_name: "reports",
          priority: 0,
          attempt: 0,
          max_attempts: 1,
          unique_key: unique_key,
          errors: [],
          scheduled_at: now,
          attempted_at: None,
          completed_at: None,
          discarded_at: None,
          cancelled_at: Some(now),
        ),
      )

    let assert Ok(_) =
      job_store.insert(
        connection,
        job_store.JobInsert(
          worker_name: "ActiveJobWorker",
          payload: "{}",
          state: job.Pending,
          queue_name: "reports",
          priority: 0,
          attempt: 0,
          max_attempts: 1,
          unique_key: unique_key,
          errors: [],
          scheduled_at: now,
          attempted_at: None,
          completed_at: None,
          discarded_at: None,
          cancelled_at: None,
        ),
      )

    let duplicate_result =
      job_store.insert(
        connection,
        job_store.JobInsert(
          worker_name: "DuplicateActiveJobWorker",
          payload: "{}",
          state: job.Pending,
          queue_name: "reports",
          priority: 0,
          attempt: 0,
          max_attempts: 1,
          unique_key: unique_key,
          errors: [],
          scheduled_at: now,
          attempted_at: None,
          completed_at: None,
          discarded_at: None,
          cancelled_at: None,
        ),
      )

    case duplicate_result {
      Error(error) -> {
        assert job_store.is_active_unique_key_conflict(error)
      }
      _ -> panic as "expected unique key violation"
    }
  })
}
