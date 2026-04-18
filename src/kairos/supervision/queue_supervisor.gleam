import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import kairos/job_runner
import kairos/supervision/queue_runtime
import kairos/supervision/registered_supervisor
import kairos/supervision/stub_actor

@internal
pub fn start(
  runtime runtime: queue_runtime.QueueRuntime,
) -> Result(actor.Started(queue_runtime.QueueRuntime), actor.StartError) {
  let builder =
    static_supervisor.new(static_supervisor.OneForAll)
    |> static_supervisor.add(
      factory_supervisor.worker_child(job_runner.start)
      |> factory_supervisor.named(queue_runtime.runner_supervisor_name(runtime))
      |> factory_supervisor.supervised,
    )
    |> static_supervisor.add(
      stub_actor.supervised(name: queue_runtime.poller_name(runtime)),
    )

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
  runtime runtime: queue_runtime.QueueRuntime,
) -> ChildSpecification(queue_runtime.QueueRuntime) {
  supervision.supervisor(fn() { start(runtime: runtime) })
}
