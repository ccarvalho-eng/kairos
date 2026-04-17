import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import kairos/config
import kairos/internal/named_supervisor
import kairos/queue_supervisor

pub opaque type Runtime {
  Runtime(root_name: process.Name(Nil), queues: List(queue_supervisor.Runtime))
}

pub fn start(
  config config: config.Config,
) -> Result(actor.Started(Runtime), actor.StartError) {
  let queues = config.queues(config)
  let queue_runtimes = queues |> list.map(queue_supervisor.from_queue)
  let builder =
    queues
    |> list.fold(
      static_supervisor.new(static_supervisor.OneForOne),
      fn(builder, queue) {
        builder
        |> static_supervisor.add(queue_supervisor.supervised(queue: queue))
      },
    )

  case
    named_supervisor.start(
      config.root_name(config),
      builder,
      "kairos root supervisor name already registered",
    )
  {
    Ok(started) ->
      Ok(actor.Started(
        pid: started.pid,
        data: Runtime(
          root_name: config.root_name(config),
          queues: queue_runtimes,
        ),
      ))

    Error(error) -> Error(error)
  }
}

pub fn supervised(config config: config.Config) -> ChildSpecification(Runtime) {
  supervision.supervisor(fn() { start(config: config) })
}

pub fn queue_names(runtime: Runtime) -> List(String) {
  let Runtime(queues:, ..) = runtime
  queues |> list.map(queue_supervisor.name)
}

pub fn has_queue(runtime: Runtime, queue_name: String) -> Bool {
  let Runtime(queues:, ..) = runtime
  queues
  |> list.any(fn(queue_runtime) {
    queue_supervisor.name(queue_runtime) == queue_name
  })
}

pub fn queue_supervisor_pid(
  runtime: Runtime,
  queue_name: String,
) -> Result(process.Pid, Nil) {
  use queue_runtime <- result.try(find_queue_runtime(runtime, queue_name))
  queue_supervisor.supervisor_pid(queue_runtime)
}

pub fn queue_worker_pid(
  runtime: Runtime,
  queue_name: String,
) -> Result(process.Pid, Nil) {
  use queue_runtime <- result.try(find_queue_runtime(runtime, queue_name))
  queue_supervisor.worker_pid(queue_runtime)
}

pub fn queue_poller_pid(
  runtime: Runtime,
  queue_name: String,
) -> Result(process.Pid, Nil) {
  use queue_runtime <- result.try(find_queue_runtime(runtime, queue_name))
  queue_supervisor.poller_pid(queue_runtime)
}

pub fn root_pid(runtime: Runtime) -> Result(process.Pid, Nil) {
  let Runtime(root_name:, ..) = runtime
  process.named(root_name)
}

fn find_queue_runtime(
  runtime: Runtime,
  queue_name: String,
) -> Result(queue_supervisor.Runtime, Nil) {
  let Runtime(queues:, ..) = runtime
  list.find(queues, fn(queue_runtime) {
    queue_supervisor.name(queue_runtime) == queue_name
  })
}
