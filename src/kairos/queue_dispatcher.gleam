import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/result
import gleam/time/timestamp
import kairos/config
import kairos/job_runner
import kairos/postgres/job_store
import kairos/queue
import kairos/queue_poller
import kairos/supervision

pub type DispatchError {
  QueueRuntimeUnavailable(String)
  ClaimFailed(job_store.StoreError)
  RunnerStartFailed(actor.StartError)
}

pub fn dispatch(
  config: config.Config,
  queue_definition: queue.Queue,
  runtime: supervision.Runtime,
  now: timestamp.Timestamp,
) -> Result(List(process.Pid), DispatchError) {
  let queue_name = queue.name(queue_definition)
  let runner_supervisor_pid =
    supervision.queue_runner_supervisor_pid(runtime, queue_name)
    |> result.map_error(fn(_) { QueueRuntimeUnavailable(queue_name) })
  use _ <- result.try(runner_supervisor_pid)
  let runner_supervisor_name =
    supervision.queue_runner_supervisor_name(runtime, queue_name)
    |> result.map_error(fn(_) { QueueRuntimeUnavailable(queue_name) })
  use runner_supervisor_name <- result.try(runner_supervisor_name)

  let claimed_jobs =
    queue_poller.poll(config.connection(config), queue_definition, now)
    |> result.map_error(ClaimFailed)
  use claimed_jobs <- result.try(claimed_jobs)

  let runner_supervisor = factory_supervisor.get_by_name(runner_supervisor_name)

  start_claimed_jobs(runner_supervisor, config, claimed_jobs, now, [])
}

fn start_claimed_jobs(
  runner_supervisor: factory_supervisor.Supervisor(job_runner.RunnerArg, String),
  config: config.Config,
  claimed_jobs: List(job_store.PersistedJob),
  now: timestamp.Timestamp,
  started_pids: List(process.Pid),
) -> Result(List(process.Pid), DispatchError) {
  case claimed_jobs {
    [] -> Ok(list.reverse(started_pids))
    [claimed_job, ..rest] -> {
      let start_result =
        factory_supervisor.start_child(
          runner_supervisor,
          job_runner.RunnerArg(config:, job: claimed_job, now: now),
        )
        |> result.map_error(RunnerStartFailed)

      use started <- result.try(start_result)
      start_claimed_jobs(runner_supervisor, config, rest, now, [
        started.pid,
        ..started_pids
      ])
    }
  }
}
