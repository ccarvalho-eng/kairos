import gleam/list
import gleam/option.{None}
import gleam/time/timestamp
import gleeunit
import kairos/job
import kairos/postgres/job_store
import kairos/postgres/test_db
import kairos/queue
import kairos/queue_poller
import pog

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn poll_claims_up_to_queue_concurrency_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let assert Ok(queue_definition) =
      queue.new(name: "default", concurrency: 2, poll_interval_ms: 1000)

    let assert Ok(_) = insert_pending(connection, "FirstWorker", now, 10)
    let assert Ok(_) = insert_pending(connection, "SecondWorker", now, 5)
    let assert Ok(_) = insert_pending(connection, "ThirdWorker", now, 1)

    let assert Ok(claimed) =
      queue_poller.poll(connection, queue_definition, now)

    assert worker_names(claimed) == ["FirstWorker", "SecondWorker"]
  })
}

fn insert_pending(
  connection: pog.Connection,
  worker_name: String,
  scheduled_at: timestamp.Timestamp,
  priority: Int,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  job_store.insert(
    connection,
    job_store.JobInsert(
      worker_name: worker_name,
      payload: "{}",
      state: job.Pending,
      queue_name: "default",
      priority: priority,
      attempt: 0,
      max_attempts: 3,
      unique_key: None,
      errors: [],
      scheduled_at: scheduled_at,
      attempted_at: None,
      completed_at: None,
      discarded_at: None,
      cancelled_at: None,
    ),
  )
}

fn worker_names(claimed_jobs: List(job_store.PersistedJob)) -> List(String) {
  claimed_jobs
  |> list.map(fn(claimed_job) {
    let job_store.PersistedJob(worker_name:, ..) = claimed_job
    worker_name
  })
}
