//// PostgreSQL persistence primitives for Kairos jobs.

import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import gleam/time/timestamp
import kairos/job
import kairos/postgres/schema
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
      constraint == schema.active_unique_key_constraint
    _ -> False
  }
}

type RawPersistedJob {
  RawPersistedJob(
    id: String,
    worker_name: String,
    payload: String,
    state: String,
    queue_name: String,
    priority: Int,
    attempt: Int,
    max_attempts: Int,
    unique_key: Option(String),
    errors: List(String),
    scheduled_at_microseconds: Int,
    attempted_at_microseconds: Option(Int),
    completed_at_microseconds: Option(Int),
    discarded_at_microseconds: Option(Int),
    cancelled_at_microseconds: Option(Int),
    inserted_at_microseconds: Int,
    updated_at_microseconds: Int,
  )
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

  "
  INSERT INTO kairos_jobs (
    worker_name,
    payload,
    state,
    queue_name,
    priority,
    attempt,
    max_attempts,
    unique_key,
    errors,
    scheduled_at,
    attempted_at,
    completed_at,
    discarded_at,
    cancelled_at
  )
  VALUES (
    $1::TEXT,
    $2::TEXT,
    $3::TEXT,
    $4::TEXT,
    $5::INTEGER,
    $6::INTEGER,
    $7::INTEGER,
    $8::TEXT,
    $9::TEXT[],
    $10::TIMESTAMPTZ,
    $11::TIMESTAMPTZ,
    $12::TIMESTAMPTZ,
    $13::TIMESTAMPTZ,
    $14::TIMESTAMPTZ
  )
  RETURNING
    id::TEXT,
    worker_name,
    payload,
    state,
    queue_name,
    priority,
    attempt,
    max_attempts,
    unique_key,
    errors,
    (EXTRACT(EPOCH FROM scheduled_at) * 1000000)::BIGINT,
    CASE
      WHEN attempted_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM attempted_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN completed_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM completed_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN discarded_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM discarded_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN cancelled_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM cancelled_at) * 1000000)::BIGINT
    END,
    (EXTRACT(EPOCH FROM inserted_at) * 1000000)::BIGINT,
    (EXTRACT(EPOCH FROM updated_at) * 1000000)::BIGINT
  "
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
  |> db.returning(raw_job_decoder())
  |> db.execute(connection)
  |> map_single_row_result
}

pub fn fetch(
  connection: db.Connection,
  id: String,
) -> Result(Option(PersistedJob), StoreError) {
  "
  SELECT
    id::TEXT,
    worker_name,
    payload,
    state,
    queue_name,
    priority,
    attempt,
    max_attempts,
    unique_key,
    errors,
    (EXTRACT(EPOCH FROM scheduled_at) * 1000000)::BIGINT,
    CASE
      WHEN attempted_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM attempted_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN completed_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM completed_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN discarded_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM discarded_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN cancelled_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM cancelled_at) * 1000000)::BIGINT
    END,
    (EXTRACT(EPOCH FROM inserted_at) * 1000000)::BIGINT,
    (EXTRACT(EPOCH FROM updated_at) * 1000000)::BIGINT
  FROM kairos_jobs
  WHERE id = $1
  "
  |> db.query
  |> db.parameter(db.text(id))
  |> db.returning(raw_job_decoder())
  |> db.execute(connection)
  |> map_optional_row_result
}

pub fn fetch_available(
  connection: db.Connection,
  now: timestamp.Timestamp,
  limit: Int,
) -> Result(List(PersistedJob), StoreError) {
  "
  SELECT
    id::TEXT,
    worker_name,
    payload,
    state,
    queue_name,
    priority,
    attempt,
    max_attempts,
    unique_key,
    errors,
    (EXTRACT(EPOCH FROM scheduled_at) * 1000000)::BIGINT,
    CASE
      WHEN attempted_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM attempted_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN completed_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM completed_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN discarded_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM discarded_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN cancelled_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM cancelled_at) * 1000000)::BIGINT
    END,
    (EXTRACT(EPOCH FROM inserted_at) * 1000000)::BIGINT,
    (EXTRACT(EPOCH FROM updated_at) * 1000000)::BIGINT
  FROM kairos_jobs
  WHERE state IN ('pending', 'scheduled', 'retryable')
    AND scheduled_at <= $1
  ORDER BY priority DESC, scheduled_at ASC, inserted_at ASC
  LIMIT $2
  "
  |> db.query
  |> db.parameter(db.timestamp(now))
  |> db.parameter(db.int(limit))
  |> db.returning(raw_job_decoder())
  |> db.execute(connection)
  |> map_many_row_result
}

fn raw_job_decoder() -> decode.Decoder(RawPersistedJob) {
  {
    use id <- decode.field(0, decode.string)
    use worker_name <- decode.field(1, decode.string)
    use payload <- decode.field(2, decode.string)
    use state <- decode.field(3, decode.string)
    use queue_name <- decode.field(4, decode.string)
    use priority <- decode.field(5, decode.int)
    use attempt <- decode.field(6, decode.int)
    use max_attempts <- decode.field(7, decode.int)
    use unique_key <- decode.field(8, decode.optional(decode.string))
    use errors <- decode.field(9, decode.list(decode.string))
    use scheduled_at_microseconds <- decode.field(10, decode.int)
    use attempted_at_microseconds <- decode.field(
      11,
      decode.optional(decode.int),
    )
    use completed_at_microseconds <- decode.field(
      12,
      decode.optional(decode.int),
    )
    use discarded_at_microseconds <- decode.field(
      13,
      decode.optional(decode.int),
    )
    use cancelled_at_microseconds <- decode.field(
      14,
      decode.optional(decode.int),
    )
    use inserted_at_microseconds <- decode.field(15, decode.int)
    use updated_at_microseconds <- decode.field(16, decode.int)

    decode.success(RawPersistedJob(
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
      scheduled_at_microseconds: scheduled_at_microseconds,
      attempted_at_microseconds: attempted_at_microseconds,
      completed_at_microseconds: completed_at_microseconds,
      discarded_at_microseconds: discarded_at_microseconds,
      cancelled_at_microseconds: cancelled_at_microseconds,
      inserted_at_microseconds: inserted_at_microseconds,
      updated_at_microseconds: updated_at_microseconds,
    ))
  }
}

fn map_single_row_result(
  result: Result(db.Returned(RawPersistedJob), db.QueryError),
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
  result: Result(db.Returned(RawPersistedJob), db.QueryError),
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
  result: Result(db.Returned(RawPersistedJob), db.QueryError),
) -> Result(List(PersistedJob), StoreError) {
  case result {
    Error(error) -> Error(QueryFailed(error))
    Ok(db.Returned(rows:, ..)) -> collect_jobs(rows)
  }
}

fn collect_jobs(
  rows: List(RawPersistedJob),
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
    Ok(job) -> Ok(Some(job))
    Error(error) -> Error(error)
  }
}

fn to_persisted_job(raw: RawPersistedJob) -> Result(PersistedJob, StoreError) {
  let RawPersistedJob(
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
        scheduled_at: microseconds_to_timestamp(scheduled_at_microseconds),
        attempted_at: option_microseconds_to_timestamp(
          attempted_at_microseconds,
        ),
        completed_at: option_microseconds_to_timestamp(
          completed_at_microseconds,
        ),
        discarded_at: option_microseconds_to_timestamp(
          discarded_at_microseconds,
        ),
        cancelled_at: option_microseconds_to_timestamp(
          cancelled_at_microseconds,
        ),
        inserted_at: microseconds_to_timestamp(inserted_at_microseconds),
        updated_at: microseconds_to_timestamp(updated_at_microseconds),
      ))
    Error(_) -> Error(InvalidJobState(raw_state))
  }
}

fn microseconds_to_timestamp(microseconds: Int) -> timestamp.Timestamp {
  let seconds = microseconds / 1_000_000
  let nanoseconds = { microseconds % 1_000_000 } * 1000
  timestamp.from_unix_seconds_and_nanoseconds(seconds, nanoseconds)
}

fn option_microseconds_to_timestamp(
  microseconds: Option(Int),
) -> Option(timestamp.Timestamp) {
  case microseconds {
    Some(value) -> Some(microseconds_to_timestamp(value))
    None -> None
  }
}
