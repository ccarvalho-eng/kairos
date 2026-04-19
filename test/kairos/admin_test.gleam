import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/time/timestamp
import gleeunit
import kairos/admin
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

pub fn list_filters_jobs_by_id_queue_worker_and_state_test() {
  test_db.with_database(fn(connection) {
    let kairos_config = build_config(connection)
    let now = timestamp.system_time()
    let alpha_email =
      insert_job(
        connection,
        worker_name: "workers.email",
        payload: "alpha-email",
        state: job.Pending,
        queue_name: "alpha",
        attempt: 0,
        max_attempts: 5,
        scheduled_at: now,
        errors: [],
      )
    let alpha_cleanup =
      insert_job(
        connection,
        worker_name: "workers.cleanup",
        payload: "alpha-cleanup",
        state: job.Retryable,
        queue_name: "alpha",
        attempt: 2,
        max_attempts: 5,
        scheduled_at: now,
        errors: ["kind=retry attempt=1 reason=temporary failure"],
      )
    let beta_email =
      insert_job(
        connection,
        worker_name: "workers.email",
        payload: "beta-email",
        state: job.Discarded,
        queue_name: "beta",
        attempt: 3,
        max_attempts: 3,
        scheduled_at: now,
        errors: ["kind=discard attempt=3 reason=permanent failure"],
      )
    let job_store.PersistedJob(id: alpha_cleanup_id, ..) = alpha_cleanup
    let job_store.PersistedJob(id: alpha_email_id, ..) = alpha_email
    let job_store.PersistedJob(id: beta_email_id, ..) = beta_email

    let assert Ok(queue_jobs) =
      admin.list(kairos_config, admin.new_query() |> admin.with_queue("alpha"))
    assert list.length(queue_jobs) == 2
    assert list.all(queue_jobs, fn(snapshot) {
      let job.JobSnapshot(queue_name:, ..) = snapshot
      queue_name == "alpha"
    })

    let assert Ok(worker_jobs) =
      admin.list(
        kairos_config,
        admin.new_query() |> admin.with_worker("workers.email"),
      )
    assert list.length(worker_jobs) == 2
    assert list.all(worker_jobs, fn(snapshot) {
      let job.JobSnapshot(worker_name:, ..) = snapshot
      worker_name == "workers.email"
    })

    let assert Ok([discarded_job]) =
      admin.list(
        kairos_config,
        admin.new_query() |> admin.with_state(job.Discarded),
      )
    let job.JobSnapshot(
      id: discarded_id,
      state: discarded_state,
      queue_name: discarded_queue,
      payload: discarded_payload,
      ..,
    ) = discarded_job
    assert discarded_id == beta_email_id
    assert discarded_state == job.Discarded
    assert discarded_queue == "beta"
    assert discarded_payload == "beta-email"

    let terminal_query =
      admin.new_query() |> admin.with_states([job.Discarded, job.Retryable])
    let assert Ok(terminal_jobs) = admin.list(kairos_config, terminal_query)
    let terminal_ids =
      terminal_jobs
      |> list.map(fn(snapshot) {
        let job.JobSnapshot(id:, ..) = snapshot
        id
      })
    assert list.length(terminal_jobs) == 2
    assert list.contains(terminal_ids, alpha_cleanup_id)
    assert list.contains(terminal_ids, beta_email_id)

    let all_query = admin.new_query() |> admin.with_states([])
    let assert Ok(all_jobs) = admin.list(kairos_config, all_query)
    assert list.length(all_jobs) == 3

    let assert Ok(limited_query) =
      admin.new_query()
      |> admin.with_states([])
      |> admin.with_limit(2)
    let assert Ok(limited_jobs) = admin.list(kairos_config, limited_query)
    assert list.length(limited_jobs) == 2

    let assert Ok([filtered_job]) =
      admin.list(
        kairos_config,
        admin.new_query() |> admin.with_id(alpha_cleanup_id),
      )
    let job.JobSnapshot(
      id: filtered_id,
      state: filtered_state,
      queue_name: filtered_queue,
      worker_name: filtered_worker,
      payload: filtered_payload,
      ..,
    ) = filtered_job
    assert filtered_id == alpha_cleanup_id
    assert filtered_state == job.Retryable
    assert filtered_queue == "alpha"
    assert filtered_worker == "workers.cleanup"
    assert filtered_payload == "alpha-cleanup"

    let returned_ids =
      queue_jobs
      |> list.map(fn(snapshot) {
        let job.JobSnapshot(id:, ..) = snapshot
        id
      })
    assert list.contains(returned_ids, alpha_email_id)
    assert list.contains(returned_ids, alpha_cleanup_id)
    assert list.contains(returned_ids, beta_email_id) == False
  })
}

pub fn with_limit_rejects_non_positive_limits_test() {
  let assert Error(admin.NonPositiveLimit) =
    admin.new_query() |> admin.with_limit(0)
  let assert Error(admin.NonPositiveLimit) =
    admin.new_query() |> admin.with_limit(-1)

  Nil
}

pub fn retry_at_requeues_cancelled_and_discarded_jobs_test() {
  test_db.with_database(fn(connection) {
    let kairos_config = build_config(connection)
    let original_time = timestamp.system_time()
    let discarded_job =
      insert_job(
        connection,
        worker_name: "workers.discarded",
        payload: "discarded",
        state: job.Discarded,
        queue_name: "default",
        attempt: 3,
        max_attempts: 3,
        scheduled_at: original_time,
        errors: ["kind=discard attempt=3 reason=permanent failure"],
      )
    let cancelled_job =
      insert_job(
        connection,
        worker_name: "workers.cancelled",
        payload: "cancelled",
        state: job.Cancelled,
        queue_name: "default",
        attempt: 0,
        max_attempts: 1,
        scheduled_at: original_time,
        errors: ["kind=cancel attempt=0 reason=cancelled before execution"],
      )
    let retry_at = timestamp.system_time()
    let expected_retry_at = test_db.to_postgres_precision(retry_at)
    let job_store.PersistedJob(id: discarded_id, ..) = discarded_job
    let job_store.PersistedJob(id: cancelled_id, ..) = cancelled_job

    let assert Ok(Nil) = admin.retry_at(kairos_config, discarded_id, retry_at)
    let assert Ok(Nil) = admin.retry_at(kairos_config, cancelled_id, retry_at)

    let assert Ok(Some(retried_discarded)) =
      job_store.fetch(connection, discarded_id)
    let assert Ok(Some(retried_cancelled)) =
      job_store.fetch(connection, cancelled_id)

    assert_retried(
      retried_discarded,
      expected_retry_at,
      expected_attempt: 3,
      expected_max_attempts: 4,
      expected_errors: ["kind=discard attempt=3 reason=permanent failure"],
    )
    assert_retried(
      retried_cancelled,
      expected_retry_at,
      expected_attempt: 0,
      expected_max_attempts: 1,
      expected_errors: [
        "kind=cancel attempt=0 reason=cancelled before execution",
      ],
    )
  })
}

pub fn retry_at_rejects_non_retryable_states_test() {
  test_db.with_database(fn(connection) {
    let kairos_config = build_config(connection)
    let now = timestamp.system_time()
    let pending_job =
      insert_job(
        connection,
        worker_name: "workers.pending",
        payload: "pending",
        state: job.Pending,
        queue_name: "default",
        attempt: 0,
        max_attempts: 5,
        scheduled_at: now,
        errors: [],
      )
    let completed_job =
      insert_job(
        connection,
        worker_name: "workers.completed",
        payload: "completed",
        state: job.Completed,
        queue_name: "default",
        attempt: 1,
        max_attempts: 5,
        scheduled_at: now,
        errors: [],
      )
    let job_store.PersistedJob(id: pending_id, ..) = pending_job
    let job_store.PersistedJob(id: completed_id, ..) = completed_job

    let assert Error(admin.JobNotRetryable(job.Pending)) =
      admin.retry_at(kairos_config, pending_id, now)
    let assert Error(admin.JobNotRetryable(job.Completed)) =
      admin.retry_at(kairos_config, completed_id, now)

    Nil
  })
}

pub fn retry_at_returns_not_found_for_missing_jobs_test() {
  test_db.with_database(fn(connection) {
    let kairos_config = build_config(connection)
    let missing_id = "00000000-0000-0000-0000-000000000000"

    let assert Error(admin.JobNotFound(id)) =
      admin.retry_at(kairos_config, missing_id, timestamp.system_time())
    assert id == missing_id

    Nil
  })
}

fn build_config(connection: pog.Connection) -> config.Config {
  let assert Ok(default_queue) =
    queue.new(name: "default", concurrency: 5, poll_interval_ms: 1000)
  let assert Ok(alpha_queue) =
    queue.new(name: "alpha", concurrency: 5, poll_interval_ms: 1000)
  let assert Ok(beta_queue) =
    queue.new(name: "beta", concurrency: 5, poll_interval_ms: 1000)
  let contract = example_worker()
  let assert Ok(kairos_config) =
    config.new(
      connection: connection,
      queues: [
        default_queue,
        alpha_queue,
        beta_queue,
      ],
      workers: [worker.register(contract)],
    )

  kairos_config
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

fn insert_job(
  connection: pog.Connection,
  worker_name worker_name: String,
  payload payload: String,
  state state: job.JobState,
  queue_name queue_name: String,
  attempt attempt: Int,
  max_attempts max_attempts: Int,
  scheduled_at scheduled_at: timestamp.Timestamp,
  errors errors: List(String),
) -> job_store.PersistedJob {
  let assert Ok(persisted_job) =
    job_store.insert(
      connection,
      job_store.JobInsert(
        worker_name: worker_name,
        payload: payload,
        state: state,
        queue_name: queue_name,
        priority: 0,
        attempt: attempt,
        max_attempts: max_attempts,
        unique_key: None,
        errors: errors,
        scheduled_at: scheduled_at,
        attempted_at: attempted_at_for(state, scheduled_at, attempt),
        completed_at: terminal_timestamp_for(state, job.Completed, scheduled_at),
        discarded_at: terminal_timestamp_for(state, job.Discarded, scheduled_at),
        cancelled_at: terminal_timestamp_for(state, job.Cancelled, scheduled_at),
      ),
    )

  persisted_job
}

fn attempted_at_for(
  state: job.JobState,
  scheduled_at: timestamp.Timestamp,
  attempt: Int,
) -> Option(timestamp.Timestamp) {
  case attempt > 0 || state == job.Executing {
    True -> Some(scheduled_at)
    False -> None
  }
}

fn terminal_timestamp_for(
  actual_state: job.JobState,
  terminal_state: job.JobState,
  timestamp: timestamp.Timestamp,
) -> Option(timestamp.Timestamp) {
  case actual_state == terminal_state {
    True -> Some(timestamp)
    False -> None
  }
}

fn assert_retried(
  persisted_job: job_store.PersistedJob,
  expected_retry_at: timestamp.Timestamp,
  expected_attempt expected_attempt: Int,
  expected_max_attempts expected_max_attempts: Int,
  expected_errors expected_errors: List(String),
) -> Nil {
  let job_store.PersistedJob(
    state: state,
    attempt: attempt,
    max_attempts: max_attempts,
    scheduled_at: scheduled_at,
    attempted_at: attempted_at,
    completed_at: completed_at,
    discarded_at: discarded_at,
    cancelled_at: cancelled_at,
    errors: errors,
    ..,
  ) = persisted_job

  assert state == job.Pending
  assert attempt == expected_attempt
  assert max_attempts == expected_max_attempts
  assert scheduled_at == expected_retry_at
  assert attempted_at == None
  assert completed_at == None
  assert discarded_at == None
  assert cancelled_at == None
  assert errors == expected_errors
}
