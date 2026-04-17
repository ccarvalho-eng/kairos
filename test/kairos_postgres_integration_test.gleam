import envoy
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import kairos/job
import kairos/postgres/jobs
import kairos/postgres/schema
import pog

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn insert_and_fetch_job_test() {
  with_database(fn(connection) {
    let now = timestamp.system_time()
    let insert =
      jobs.JobInsert(
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

    let assert Ok(inserted) = jobs.insert(connection, insert)
    let jobs.PersistedJob(
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

    let assert Ok(Some(fetched)) = jobs.fetch(connection, id)
    let jobs.PersistedJob(id: fetched_id, state: fetched_state, ..) = fetched

    assert fetched_id == id
    assert fetched_state == job.Pending
  })
}

pub fn fetch_available_respects_schedule_and_priority_test() {
  with_database(fn(connection) {
    let now = timestamp.system_time()
    let later = timestamp.add(now, duration.minutes(5))

    let assert Ok(_) =
      jobs.insert(
        connection,
        jobs.JobInsert(
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
      jobs.insert(
        connection,
        jobs.JobInsert(
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

    let assert Ok(available_now) = jobs.fetch_available(connection, now, 10)
    assert list.length(available_now) == 1

    let assert [first] = available_now
    let jobs.PersistedJob(worker_name: first_name, ..) = first
    assert first_name == "ImmediateWorker"

    let assert Ok(available_later) =
      jobs.fetch_available(
        connection,
        timestamp.add(later, duration.seconds(1)),
        10,
      )

    assert list.length(available_later) == 2

    let assert [scheduled_first, immediate_second] = available_later
    let jobs.PersistedJob(worker_name: scheduled_name, ..) = scheduled_first
    let jobs.PersistedJob(worker_name: immediate_name, ..) = immediate_second

    assert scheduled_name == "ScheduledWorker"
    assert immediate_name == "ImmediateWorker"
  })
}

pub fn unique_key_only_blocks_active_jobs_test() {
  with_database(fn(connection) {
    let now = timestamp.system_time()
    let unique_key = Some("daily-report")

    let assert Ok(_) =
      jobs.insert(
        connection,
        jobs.JobInsert(
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
      jobs.insert(
        connection,
        jobs.JobInsert(
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
      jobs.insert(
        connection,
        jobs.JobInsert(
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
        assert jobs.is_active_unique_key_conflict(error)
      }
      _ -> panic as "expected unique key violation"
    }
  })
}

pub fn retryable_and_terminal_state_round_trip_test() {
  with_database(fn(connection) {
    let now = timestamp.system_time()

    let assert Ok(retryable) =
      jobs.insert(
        connection,
        jobs.JobInsert(
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

    let jobs.PersistedJob(id: retryable_id, errors: retryable_errors, ..) =
      retryable
    assert retryable_errors == ["timeout", "database busy"]

    let assert Ok(available) = jobs.fetch_available(connection, now, 10)
    let retryable_names =
      available
      |> list.map(fn(job) {
        let jobs.PersistedJob(worker_name: worker_name, ..) = job
        worker_name
      })

    assert list.contains(retryable_names, "RetryableWorker")

    let assert Ok(completed) =
      jobs.insert(
        connection,
        jobs.JobInsert(
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
      jobs.insert(
        connection,
        jobs.JobInsert(
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

    let jobs.PersistedJob(id: completed_id, completed_at: completed_at, ..) =
      completed
    let jobs.PersistedJob(
      id: discarded_id,
      discarded_at: discarded_at,
      errors: discarded_errors,
      ..,
    ) = discarded

    let expected_now = to_postgres_precision(now)

    assert completed_at == Some(expected_now)
    assert discarded_at == Some(expected_now)
    assert discarded_errors == ["poison payload"]

    let assert Ok(Some(fetched_retryable)) =
      jobs.fetch(connection, retryable_id)
    let assert Ok(Some(fetched_completed)) =
      jobs.fetch(connection, completed_id)
    let assert Ok(Some(fetched_discarded)) =
      jobs.fetch(connection, discarded_id)

    let jobs.PersistedJob(state: retryable_state, ..) = fetched_retryable
    let jobs.PersistedJob(state: completed_state, ..) = fetched_completed
    let jobs.PersistedJob(state: discarded_state, ..) = fetched_discarded

    assert retryable_state == job.Retryable
    assert completed_state == job.Completed
    assert discarded_state == job.Discarded
  })
}

fn with_database(run: fn(pog.Connection) -> Nil) -> Nil {
  let name = process.new_name("kairos_postgres_test")
  let assert Ok(database_url) = envoy.get("KAIROS_TEST_DATABASE_URL")
    as "Set KAIROS_TEST_DATABASE_URL to a dedicated PostgreSQL test database before running integration tests."

  let assert Ok(config) = pog.url_config(name, database_url)
  let assert Ok(actor.Started(pid: pid, data: connection)) = pog.start(config)

  wait_for_connection(connection, 20)
  reset_schema(connection)
  run(connection)
  process.send_exit(pid)
}

fn wait_for_connection(connection: pog.Connection, remaining: Int) -> Nil {
  case pog.query("SELECT 1") |> pog.execute(connection) {
    Ok(_) -> Nil
    Error(_) ->
      case remaining {
        0 -> {
          let assert Ok(_) = pog.query("SELECT 1") |> pog.execute(connection)
          Nil
        }
        _ -> {
          process.sleep(50)
          wait_for_connection(connection, remaining - 1)
        }
      }
  }
}

fn reset_schema(connection: pog.Connection) -> Nil {
  [
    "DROP TRIGGER IF EXISTS kairos_jobs_set_updated_at ON kairos_jobs",
    "DROP FUNCTION IF EXISTS kairos_touch_updated_at()",
    "DROP TABLE IF EXISTS kairos_jobs",
  ]
  |> execute_statements(connection)

  let schema.Migration(statements:, ..) = schema.initial_migration()
  execute_statements(statements, connection)
}

fn execute_statements(
  statements: List(String),
  connection: pog.Connection,
) -> Nil {
  case statements {
    [] -> Nil
    [statement, ..rest] -> {
      let assert Ok(_) = pog.query(statement) |> pog.execute(connection)
      execute_statements(rest, connection)
    }
  }
}

fn to_postgres_precision(timestamp: timestamp.Timestamp) -> timestamp.Timestamp {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)

  timestamp.from_unix_seconds_and_nanoseconds(
    seconds,
    { nanoseconds / 1000 } * 1000,
  )
}
