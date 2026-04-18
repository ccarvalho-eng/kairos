import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import kairos/config
import kairos/job
import kairos/postgres/job_store
import kairos/queue
import kairos/queue_reaper
import kairos/supervision as kairos_supervision
import kairos/worker
import pog

pub type EnqueueError {
  QueueNotConfigured(String)
  StoreQueryFailed
  UnexpectedStoredRowCount(expected: Int, actual: Int)
  InvalidStoredState(String)
}

pub type CancelError {
  JobNotFound(String)
  JobNotCancellable(job.JobState)
  CancelStoreQueryFailed
  CancelInvalidStoredState(String)
  CancelUnexpectedStoredRowCount(expected: Int, actual: Int)
}

pub type RecoveryError {
  QueueRuntimeUnavailable(String)
  RecoveryStoreQueryFailed
  RecoveryInvalidStoredState(String)
  RecoveryUnexpectedStoredRowCount(expected: Int, actual: Int)
}

pub fn package_name() -> String {
  "kairos"
}

pub fn start(
  config: config.Config,
) -> Result(actor.Started(kairos_supervision.Runtime), actor.StartError) {
  kairos_supervision.start(config: config)
}

pub fn supervised(
  config: config.Config,
) -> ChildSpecification(kairos_supervision.Runtime) {
  kairos_supervision.supervised(config: config)
}

pub fn enqueue(
  config: config.Config,
  contract: worker.Worker(args),
  args: args,
) -> Result(job.EnqueuedJob(args), EnqueueError) {
  enqueue_with(config, contract, args, worker.default_options(contract))
}

pub fn enqueue_with(
  config: config.Config,
  contract: worker.Worker(args),
  args: args,
  options: job.EnqueueOptions,
) -> Result(job.EnqueuedJob(args), EnqueueError) {
  let queue_name = job.queue(options)
  case validate_queue(config, queue_name) {
    Error(error) -> Error(error)
    Ok(Nil) -> {
      let #(scheduled_at, state) = schedule_context(options)
      let new_job =
        job_store.JobInsert(
          worker_name: worker.name(contract),
          payload: worker.encode(contract, args),
          state: state,
          queue_name: queue_name,
          priority: job.priority(options),
          attempt: 0,
          max_attempts: job.max_attempts(options),
          unique_key: None,
          errors: [],
          scheduled_at: scheduled_at,
          attempted_at: None,
          completed_at: None,
          discarded_at: None,
          cancelled_at: None,
        )

      case job_store.insert(config.connection(config), new_job) {
        Ok(persisted) -> Ok(to_enqueued_job(persisted, args))
        Error(error) -> Error(map_store_error(error))
      }
    }
  }
}

@internal
pub fn cancel_at(
  config: config.Config,
  id: String,
  now: timestamp.Timestamp,
) -> Result(Nil, CancelError) {
  pog.transaction(config.connection(config), fn(connection) {
    let fetched =
      job_store.fetch_for_update(connection, id)
      |> result.map_error(map_cancel_store_error)
    use fetched <- result.try(fetched)

    case fetched {
      None -> Error(JobNotFound(id))
      Some(persisted_job) -> {
        let job_store.PersistedJob(state:, attempt:, ..) = persisted_job

        case can_cancel(state) {
          True -> {
            let error = cancel_error(attempt)
            let cancelled =
              job_store.cancel_before_execution(connection, id, now, error)
              |> result.map_error(map_cancel_store_error)
            use _ <- result.try(cancelled)
            Ok(Nil)
          }
          False -> Error(JobNotCancellable(state))
        }
      }
    }
  })
  |> map_cancel_transaction_error
}

pub fn cancel(config: config.Config, id: String) -> Result(Nil, CancelError) {
  cancel_at(config, id, timestamp.system_time())
}

pub fn recover_stale(
  runtime: kairos_supervision.Runtime,
  queue_name: String,
  now: timestamp.Timestamp,
  stale_for: duration.Duration,
) -> Result(Int, RecoveryError) {
  let reaper_name =
    kairos_supervision.queue_reaper_name(runtime, queue_name)
    |> result.map_error(fn(_) { QueueRuntimeUnavailable(queue_name) })
  use reaper_name <- result.try(reaper_name)

  queue_reaper.recover(reaper_name, now, stale_for)
  |> result.map_error(map_recovery_store_error)
}

fn validate_queue(
  config: config.Config,
  queue_name: String,
) -> Result(Nil, EnqueueError) {
  case
    config.queues(config)
    |> list.any(fn(queue_definition) {
      queue.name(queue_definition) == queue_name
    })
  {
    True -> Ok(Nil)
    False -> Error(QueueNotConfigured(queue_name))
  }
}

fn schedule_context(
  options: job.EnqueueOptions,
) -> #(timestamp.Timestamp, job.JobState) {
  case job.schedule(options) {
    job.Immediately -> #(timestamp.system_time(), job.Pending)
    job.At(scheduled_at) -> #(scheduled_at, job.Scheduled)
  }
}

fn to_enqueued_job(
  persisted: job_store.PersistedJob,
  args: args,
) -> job.EnqueuedJob(args) {
  let job_store.PersistedJob(
    id: id,
    worker_name: worker_name,
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
    ..,
  ) = persisted

  job.EnqueuedJob(
    id: id,
    worker_name: worker_name,
    args: args,
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

fn map_store_error(error: job_store.StoreError) -> EnqueueError {
  case error {
    job_store.QueryFailed(_) -> StoreQueryFailed
    job_store.UnexpectedRowCount(expected:, actual:) ->
      UnexpectedStoredRowCount(expected: expected, actual: actual)
    job_store.InvalidJobState(state) -> InvalidStoredState(state)
  }
}

fn can_cancel(state: job.JobState) -> Bool {
  case state {
    job.Pending -> True
    job.Scheduled -> True
    job.Retryable -> True
    _ -> False
  }
}

fn cancel_error(attempt: Int) -> String {
  "kind=cancel attempt="
  <> int.to_string(attempt)
  <> " reason=cancelled before execution"
}

fn map_cancel_transaction_error(
  result: Result(Nil, pog.TransactionError(CancelError)),
) -> Result(Nil, CancelError) {
  case result {
    Ok(value) -> Ok(value)
    Error(pog.TransactionQueryError(_)) -> Error(CancelStoreQueryFailed)
    Error(pog.TransactionRolledBack(error)) -> Error(error)
  }
}

fn map_cancel_store_error(error: job_store.StoreError) -> CancelError {
  case error {
    job_store.QueryFailed(_) -> CancelStoreQueryFailed
    job_store.InvalidJobState(state) -> CancelInvalidStoredState(state)
    job_store.UnexpectedRowCount(expected:, actual:) ->
      CancelUnexpectedStoredRowCount(expected: expected, actual: actual)
  }
}

fn map_recovery_store_error(error: job_store.StoreError) -> RecoveryError {
  case error {
    job_store.QueryFailed(_) -> RecoveryStoreQueryFailed
    job_store.InvalidJobState(state) -> RecoveryInvalidStoredState(state)
    job_store.UnexpectedRowCount(expected:, actual:) ->
      RecoveryUnexpectedStoredRowCount(expected: expected, actual: actual)
  }
}
