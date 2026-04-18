import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/time/timestamp
import kairos/config
import kairos/job
import kairos/postgres/job_store
import kairos/queue
import kairos/supervision as kairos_supervision
import kairos/worker

pub type EnqueueError {
  QueueNotConfigured(String)
  StoreQueryFailed
  UnexpectedStoredRowCount(expected: Int, actual: Int)
  InvalidStoredState(String)
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
      let scheduled_at = schedule_at(options)
      let state = state_for_schedule(options)
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

fn schedule_at(options: job.EnqueueOptions) -> timestamp.Timestamp {
  case job.schedule(options) {
    job.Immediately -> timestamp.system_time()
    job.At(scheduled_at) -> scheduled_at
  }
}

fn state_for_schedule(options: job.EnqueueOptions) -> job.JobState {
  case job.schedule(options) {
    job.Immediately -> job.Pending
    job.At(_) -> job.Scheduled
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
