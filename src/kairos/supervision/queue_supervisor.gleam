import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import kairos/config
import kairos/runtime/job_runner
import kairos/runtime/queue_poller
import kairos/runtime/queue_reaper
import kairos/supervision/queue_runtime
import kairos/supervision/registered_supervisor

@internal
pub fn start(
  config config: config.Config,
  runtime runtime: queue_runtime.QueueRuntime,
) -> Result(actor.Started(queue_runtime.QueueRuntime), actor.StartError) {
  let builder =
    static_supervisor.new(static_supervisor.OneForAll)
    |> static_supervisor.add(
      factory_supervisor.worker_child(job_runner.start)
      |> factory_supervisor.named(queue_runtime.runner_supervisor_name(runtime))
      |> factory_supervisor.supervised,
    )
    |> static_supervisor.add(queue_poller.supervised(
      name: queue_runtime.poller_name(runtime),
      config: config,
      queue_name: queue_runtime.name(runtime),
      concurrency: queue_runtime.concurrency(runtime),
      poll_interval_ms: queue_runtime.poll_interval_ms(runtime),
      runner_supervisor_name: queue_runtime.runner_supervisor_name(runtime),
    ))
    |> static_supervisor.add(queue_reaper.supervised(
      name: queue_runtime.reaper_name(runtime),
      config: config,
      queue_name: queue_runtime.name(runtime),
    ))

  case
    registered_supervisor.start(
      queue_runtime.supervisor_name(runtime),
      builder,
      "queue supervisor name already registered",
    )
  {
    Ok(started) -> Ok(actor.Started(pid: started.pid, data: runtime))
    Error(error) -> Error(error)
  }
}

@internal
pub fn supervised(
  config config: config.Config,
  runtime runtime: queue_runtime.QueueRuntime,
) -> ChildSpecification(queue_runtime.QueueRuntime) {
  supervision.supervisor(fn() { start(config: config, runtime: runtime) })
}
