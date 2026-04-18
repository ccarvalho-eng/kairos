import gleam/option.{None, Some}
import gleam/time/timestamp
import gleeunit
import kairos/job
import kairos/postgres/job_store
import kairos/postgres/test_db

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn insert_and_fetch_job_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let insert =
      job_store.JobInsert(
        worker_name: "EmailWorker",
        payload: "{\"user_id\": 10}",
        state: job.Pending,
        queue_name: "default",
        priority: 10,
        attempt: 0,
        max_attempts: 5,
        unique_key: Some("welcome-email:10"),
        errors: [],
        scheduled_at: now,
        attempted_at: None,
        completed_at: None,
        discarded_at: None,
        cancelled_at: None,
      )

    let assert Ok(inserted) = job_store.insert(connection, insert)
    let job_store.PersistedJob(
      id: id,
      worker_name: worker_name,
      payload: payload,
      state: state,
      queue_name: queue_name,
      priority: priority,
      attempt: attempt,
      max_attempts: max_attempts,
      unique_key: unique_key,
      errors: errors,
      ..,
    ) = inserted

    assert worker_name == "EmailWorker"
    assert payload == "{\"user_id\": 10}"
    assert state == job.Pending
    assert queue_name == "default"
    assert priority == 10
    assert attempt == 0
    assert max_attempts == 5
    assert unique_key == Some("welcome-email:10")
    assert errors == []

    let assert Ok(Some(fetched)) = job_store.fetch(connection, id)
    let job_store.PersistedJob(id: fetched_id, state: fetched_state, ..) =
      fetched

    assert fetched_id == id
    assert fetched_state == job.Pending
  })
}
