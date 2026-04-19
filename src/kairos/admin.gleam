//// Administrative APIs for inspecting and mutating persisted Kairos jobs.

import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/timestamp
import kairos
import kairos/config
import kairos/job
import kairos/postgres/job_store
import pog

pub type QueryError {
  QueryStoreQueryFailed
  QueryInvalidStoredState(String)
  QueryUnexpectedStoredRowCount(expected: Int, actual: Int)
}

pub type QueryOptionError {
  NonPositiveLimit
}

pub type RetryError {
  JobNotFound(String)
  JobNotRetryable(job.JobState)
  RetryStoreQueryFailed
  RetryInvalidStoredState(String)
  RetryUnexpectedStoredRowCount(expected: Int, actual: Int)
}

pub opaque type Query {
  Query(
    id: Option(String),
    queue_name: Option(String),
    worker_name: Option(String),
    states: List(job.JobState),
    limit: Int,
  )
}

pub fn new_query() -> Query {
  Query(
    id: None,
    queue_name: None,
    worker_name: None,
    states: [],
    limit: default_query_limit(),
  )
}

pub fn with_id(query: Query, id: String) -> Query {
  let Query(queue_name:, worker_name:, states:, limit:, ..) = query
  Query(
    id: Some(id),
    queue_name: queue_name,
    worker_name: worker_name,
    states: states,
    limit: limit,
  )
}

pub fn with_queue(query: Query, queue_name: String) -> Query {
  let Query(id:, worker_name:, states:, limit:, ..) = query
  Query(
    id: id,
    queue_name: Some(queue_name),
    worker_name: worker_name,
    states: states,
    limit: limit,
  )
}

pub fn with_worker(query: Query, worker_name: String) -> Query {
  let Query(id:, queue_name:, states:, limit:, ..) = query
  Query(
    id: id,
    queue_name: queue_name,
    worker_name: Some(worker_name),
    states: states,
    limit: limit,
  )
}

pub fn with_state(query: Query, state: job.JobState) -> Query {
  let Query(id:, queue_name:, worker_name:, limit:, ..) = query
  Query(
    id: id,
    queue_name: queue_name,
    worker_name: worker_name,
    states: [state],
    limit: limit,
  )
}

pub fn with_states(query: Query, states: List(job.JobState)) -> Query {
  let Query(id:, queue_name:, worker_name:, limit:, ..) = query
  Query(
    id: id,
    queue_name: queue_name,
    worker_name: worker_name,
    states: states,
    limit: limit,
  )
}

pub fn with_limit(query: Query, limit: Int) -> Result(Query, QueryOptionError) {
  case limit <= 0 {
    True -> Error(NonPositiveLimit)
    False -> {
      let Query(id:, queue_name:, worker_name:, states:, ..) = query
      Ok(Query(
        id: id,
        queue_name: queue_name,
        worker_name: worker_name,
        states: states,
        limit: limit,
      ))
    }
  }
}

pub fn list(
  config: config.Config,
  query: Query,
) -> Result(List(job.JobSnapshot), QueryError) {
  let Query(id:, queue_name:, worker_name:, states:, limit:) = query

  job_store.list(
    config.connection(config),
    id,
    queue_name,
    worker_name,
    states,
    limit,
  )
  |> result.map(list_from_persisted)
  |> result.map_error(map_query_store_error)
}

pub fn cancel(
  config: config.Config,
  id: String,
) -> Result(Nil, kairos.CancelError) {
  kairos.cancel(config, id)
}

pub fn cancel_at(
  config: config.Config,
  id: String,
  now: timestamp.Timestamp,
) -> Result(Nil, kairos.CancelError) {
  kairos.cancel_at(config, id, now)
}

pub fn retry(config: config.Config, id: String) -> Result(Nil, RetryError) {
  retry_at(config, id, timestamp.system_time())
}

pub fn retry_at(
  config: config.Config,
  id: String,
  now: timestamp.Timestamp,
) -> Result(Nil, RetryError) {
  pog.transaction(config.connection(config), fn(connection) {
    let fetched =
      job_store.fetch_for_update(connection, id)
      |> result.map_error(map_retry_store_error)
    use fetched <- result.try(fetched)

    case fetched {
      None -> Error(JobNotFound(id))
      Some(persisted_job) -> {
        let job_store.PersistedJob(state:, ..) = persisted_job

        case can_retry(state) {
          True -> {
            let retried =
              job_store.retry_now(connection, id, now)
              |> result.map_error(map_retry_store_error)
            use _ <- result.try(retried)
            Ok(Nil)
          }
          False -> Error(JobNotRetryable(state))
        }
      }
    }
  })
  |> map_retry_transaction_error
}

fn can_retry(state: job.JobState) -> Bool {
  case state {
    job.Discarded -> True
    job.Cancelled -> True
    _ -> False
  }
}

fn default_query_limit() -> Int {
  100
}

fn list_from_persisted(
  persisted_jobs: List(job_store.PersistedJob),
) -> List(job.JobSnapshot) {
  case persisted_jobs {
    [] -> []
    [persisted_job, ..rest] -> [
      from_persisted(persisted_job),
      ..list_from_persisted(rest)
    ]
  }
}

fn from_persisted(persisted_job: job_store.PersistedJob) -> job.JobSnapshot {
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
    scheduled_at: scheduled_at,
    attempted_at: attempted_at,
    completed_at: completed_at,
    discarded_at: discarded_at,
    cancelled_at: cancelled_at,
    inserted_at: inserted_at,
    updated_at: updated_at,
  ) = persisted_job

  job.JobSnapshot(
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
    scheduled_at: scheduled_at,
    attempted_at: attempted_at,
    completed_at: completed_at,
    discarded_at: discarded_at,
    cancelled_at: cancelled_at,
    inserted_at: inserted_at,
    updated_at: updated_at,
  )
}

fn map_query_store_error(error: job_store.StoreError) -> QueryError {
  case error {
    job_store.QueryFailed(_) -> QueryStoreQueryFailed
    job_store.InvalidJobState(state) -> QueryInvalidStoredState(state)
    job_store.UnexpectedRowCount(expected:, actual:) ->
      QueryUnexpectedStoredRowCount(expected: expected, actual: actual)
  }
}

fn map_retry_transaction_error(
  result: Result(Nil, pog.TransactionError(RetryError)),
) -> Result(Nil, RetryError) {
  case result {
    Ok(value) -> Ok(value)
    Error(pog.TransactionQueryError(_)) -> Error(RetryStoreQueryFailed)
    Error(pog.TransactionRolledBack(error)) -> Error(error)
  }
}

fn map_retry_store_error(error: job_store.StoreError) -> RetryError {
  case error {
    job_store.QueryFailed(_) -> RetryStoreQueryFailed
    job_store.InvalidJobState(state) -> RetryInvalidStoredState(state)
    job_store.UnexpectedRowCount(expected:, actual:) ->
      RetryUnexpectedStoredRowCount(expected: expected, actual: actual)
  }
}
