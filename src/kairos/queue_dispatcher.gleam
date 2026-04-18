import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/result
import gleam/time/timestamp
import kairos/config
import kairos/job_runner
import kairos/postgres/job_store
import kairos/queue
import kairos/queue_dispatch
import kairos/supervision

pub type DispatchError {
  QueueRuntimeUnavailable(String)
  ClaimFailed(job_store.StoreError)
  RunnerStartFailed(actor.StartError)
  ReleaseClaimedFailed(actor.StartError, job_store.StoreError)
}

pub fn dispatch(
  config: config.Config,
  queue_definition: queue.Queue,
  runtime: supervision.Runtime,
  now: timestamp.Timestamp,
) -> Result(List(process.Pid), DispatchError) {
  let queue_name = queue.name(queue_definition)
  let runner_supervisor_name =
    supervision.queue_runner_supervisor_name(runtime, queue_name)
    |> result.map_error(fn(_) { QueueRuntimeUnavailable(queue_name) })
  use runner_supervisor_name <- result.try(runner_supervisor_name)
  let claimed_jobs =
    job_store.claim_available(
      config.connection(config),
      queue_name,
      now,
      queue.concurrency(queue_definition),
    )
    |> result.map_error(ClaimFailed)
  use claimed_jobs <- result.try(claimed_jobs)

  dispatch_claimed(
    config,
    queue_name,
    runner_supervisor_name,
    claimed_jobs,
    now,
  )
}

@internal
pub fn dispatch_claimed(
  config: config.Config,
  queue_name: String,
  runner_supervisor_name: process.Name(
    factory_supervisor.Message(job_runner.RunnerArg, String),
  ),
  claimed_jobs: List(job_store.PersistedJob),
  now: timestamp.Timestamp,
) -> Result(List(process.Pid), DispatchError) {
  queue_dispatch.dispatch_claimed(
    config,
    queue_name,
    runner_supervisor_name,
    claimed_jobs,
    now,
  )
  |> result.map_error(map_dispatch_claimed_error)
}

fn map_dispatch_claimed_error(
  error: queue_dispatch.DispatchClaimedError,
) -> DispatchError {
  case error {
    queue_dispatch.QueueRuntimeUnavailable(queue_name) ->
      QueueRuntimeUnavailable(queue_name)
    queue_dispatch.RunnerStartFailed(start_error) ->
      RunnerStartFailed(start_error)
    queue_dispatch.ReleaseClaimedFailed(start_error, cleanup_error) ->
      ReleaseClaimedFailed(start_error, cleanup_error)
  }
}
