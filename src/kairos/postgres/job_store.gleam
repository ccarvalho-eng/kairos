//// PostgreSQL persistence primitives for Kairos jobs.

import gleam/option.{type Option, None, Some}
import gleam/time/timestamp
import kairos/job
import kairos/migrations/postgres
import kairos/postgres/job_store/query
import kairos/postgres/job_store/raw_job
import kairos/postgres/job_store/timestamp as store_timestamp
import pog as db

pub type JobInsert {
  JobInsert(
    worker_name: String,
    payload: String,
    state: job.JobState,
    queue_name: String,
    priority: Int,
    attempt: Int,
    max_attempts: Int,
    unique_key: Option(String),
    errors: List(String),
    scheduled_at: timestamp.Timestamp,
    attempted_at: Option(timestamp.Timestamp),
    completed_at: Option(timestamp.Timestamp),
    discarded_at: Option(timestamp.Timestamp),
    cancelled_at: Option(timestamp.Timestamp),
  )
}

pub type PersistedJob {
  PersistedJob(
    id: String,
    worker_name: String,
    payload: String,
    state: job.JobState,
    queue_name: String,
    priority: Int,
    attempt: Int,
    max_attempts: Int,
    unique_key: Option(String),
    errors: List(String),
    scheduled_at: timestamp.Timestamp,
    attempted_at: Option(timestamp.Timestamp),
    completed_at: Option(timestamp.Timestamp),
    discarded_at: Option(timestamp.Timestamp),
    cancelled_at: Option(timestamp.Timestamp),
    inserted_at: timestamp.Timestamp,
    updated_at: timestamp.Timestamp,
  )
}

pub type StoreError {
  InvalidJobState(String)
  QueryFailed(db.QueryError)
  UnexpectedRowCount(expected: Int, actual: Int)
}

pub fn is_active_unique_key_conflict(error: StoreError) -> Bool {
  case error {
    QueryFailed(db.ConstraintViolated(_, constraint, _)) ->
      constraint == postgres.active_unique_key_constraint
    _ -> False
  }
}

pub fn insert(
  connection: db.Connection,
  new_job: JobInsert,
) -> Result(PersistedJob, StoreError) {
  let JobInsert(
    worker_name: worker_name,
    payload: payload,
    state: state,
    queue_name: queue_name,
    priority: priority,
    attempt: attempt,
    max_attempts: max_attempts,
    unique_key: unique_key,
    errors: errors,
    scheduled_at: scheduled_at,
    attempted_at: attempted_at,
    completed_at: completed_at,
    discarded_at: discarded_at,
    cancelled_at: cancelled_at,
  ) = new_job

  query.insert()
  |> db.query
  |> db.parameter(db.text(worker_name))
  |> db.parameter(db.text(payload))
  |> db.parameter(db.text(job.state_name(state)))
  |> db.parameter(db.text(queue_name))
  |> db.parameter(db.int(priority))
  |> db.parameter(db.int(attempt))
  |> db.parameter(db.int(max_attempts))
  |> db.parameter(db.nullable(db.text, unique_key))
  |> db.parameter(db.array(db.text, errors))
  |> db.parameter(db.timestamp(scheduled_at))
  |> db.parameter(db.nullable(db.timestamp, attempted_at))
  |> db.parameter(db.nullable(db.timestamp, completed_at))
  |> db.parameter(db.nullable(db.timestamp, discarded_at))
  |> db.parameter(db.nullable(db.timestamp, cancelled_at))
  |> db.returning(raw_job.decoder())
  |> db.execute(connection)
  |> map_single_row_result
}

pub fn fetch(
  connection: db.Connection,
  id: String,
) -> Result(Option(PersistedJob), StoreError) {
  query.fetch()
  |> db.query
  |> db.parameter(db.text(id))
  |> db.returning(raw_job.decoder())
  |> db.execute(connection)
  |> map_optional_row_result
}

pub fn fetch_available(
  connection: db.Connection,
  now: timestamp.Timestamp,
  limit: Int,
) -> Result(List(PersistedJob), StoreError) {
  query.fetch_available()
  |> db.query
  |> db.parameter(db.timestamp(now))
  |> db.parameter(db.int(limit))
  |> db.returning(raw_job.decoder())
  |> db.execute(connection)
  |> map_many_row_result
}

pub fn claim_available(
  connection: db.Connection,
  queue_name: String,
  now: timestamp.Timestamp,
  limit: Int,
) -> Result(List(PersistedJob), StoreError) {
  query.claim_available()
  |> db.query
  |> db.parameter(db.text(queue_name))
  |> db.parameter(db.timestamp(now))
  |> db.parameter(db.int(limit))
  |> db.returning(raw_job.decoder())
  |> db.execute(connection)
  |> map_many_row_result
}

fn map_single_row_result(
  result: Result(db.Returned(raw_job.RawPersistedJob), db.QueryError),
) -> Result(PersistedJob, StoreError) {
  case result {
    Error(error) -> Error(QueryFailed(error))
    Ok(db.Returned(count:, rows:)) ->
      case rows {
        [row] -> to_persisted_job(row)
        _ -> Error(UnexpectedRowCount(expected: 1, actual: count))
      }
  }
}

fn map_optional_row_result(
  result: Result(db.Returned(raw_job.RawPersistedJob), db.QueryError),
) -> Result(Option(PersistedJob), StoreError) {
  case result {
    Error(error) -> Error(QueryFailed(error))
    Ok(db.Returned(count:, rows:)) ->
      case rows {
        [] -> Ok(None)
        [row] -> to_persisted_job(row) |> map_ok_option
        _ -> Error(UnexpectedRowCount(expected: 1, actual: count))
      }
  }
}

fn map_many_row_result(
  result: Result(db.Returned(raw_job.RawPersistedJob), db.QueryError),
) -> Result(List(PersistedJob), StoreError) {
  case result {
    Error(error) -> Error(QueryFailed(error))
    Ok(db.Returned(rows:, ..)) -> collect_jobs(rows)
  }
}

fn collect_jobs(
  rows: List(raw_job.RawPersistedJob),
) -> Result(List(PersistedJob), StoreError) {
  case rows {
    [] -> Ok([])
    [row, ..rest] ->
      case to_persisted_job(row), collect_jobs(rest) {
        Ok(job), Ok(other_jobs) -> Ok([job, ..other_jobs])
        Error(error), _ -> Error(error)
        _, Error(error) -> Error(error)
      }
  }
}

fn map_ok_option(
  result: Result(PersistedJob, StoreError),
) -> Result(Option(PersistedJob), StoreError) {
  case result {
    Ok(persisted_job) -> Ok(Some(persisted_job))
    Error(error) -> Error(error)
  }
}

fn to_persisted_job(
  raw: raw_job.RawPersistedJob,
) -> Result(PersistedJob, StoreError) {
  let raw_job.RawPersistedJob(
    id: id,
    worker_name: worker_name,
    payload: payload,
    state: raw_state,
    queue_name: queue_name,
    priority: priority,
    attempt: attempt,
    max_attempts: max_attempts,
    unique_key: unique_key,
    errors: errors,
    scheduled_at_microseconds: scheduled_at_microseconds,
    attempted_at_microseconds: attempted_at_microseconds,
    completed_at_microseconds: completed_at_microseconds,
    discarded_at_microseconds: discarded_at_microseconds,
    cancelled_at_microseconds: cancelled_at_microseconds,
    inserted_at_microseconds: inserted_at_microseconds,
    updated_at_microseconds: updated_at_microseconds,
  ) = raw

  case job.state_from_string(raw_state) {
    Ok(state) ->
      Ok(PersistedJob(
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
        scheduled_at: store_timestamp.from_microseconds(
          scheduled_at_microseconds,
        ),
        attempted_at: store_timestamp.option_from_microseconds(
          attempted_at_microseconds,
        ),
        completed_at: store_timestamp.option_from_microseconds(
          completed_at_microseconds,
        ),
        discarded_at: store_timestamp.option_from_microseconds(
          discarded_at_microseconds,
        ),
        cancelled_at: store_timestamp.option_from_microseconds(
          cancelled_at_microseconds,
        ),
        inserted_at: store_timestamp.from_microseconds(inserted_at_microseconds),
        updated_at: store_timestamp.from_microseconds(updated_at_microseconds),
      ))
    Error(_) -> Error(InvalidJobState(raw_state))
  }
}
