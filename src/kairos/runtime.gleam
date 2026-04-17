import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import kairos/config
import kairos/queue_supervisor

pub opaque type Runtime {
  Runtime(root_name: process.Name(Nil), queues: List(queue_supervisor.Runtime))
}

pub fn start(
  config config: config.Config,
) -> Result(actor.Started(Runtime), actor.StartError) {
  let queue_runtimes =
    config.queues(config) |> list.map(queue_supervisor.from_queue)
  let builder =
    config.queues(config)
    |> list.fold(
      static_supervisor.new(static_supervisor.OneForOne),
      fn(builder, queue) {
        builder
        |> static_supervisor.add(queue_supervisor.supervised(queue: queue))
      },
    )

  case start_named_supervisor(config.root_name(config), builder) {
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
  case
    list.find(queues, fn(queue_runtime) {
      queue_supervisor.name(queue_runtime) == queue_name
    })
  {
    Ok(queue_runtime) -> Ok(queue_runtime)
    Error(Nil) -> Error(Nil)
  }
}

fn start_named_supervisor(
  name: process.Name(Nil),
  builder: static_supervisor.Builder,
) -> Result(actor.Started(static_supervisor.Supervisor), actor.StartError) {
  case static_supervisor.start(builder) {
    Ok(started) -> {
      case process.register(started.pid, name) {
        Ok(Nil) -> Ok(started)
        Error(_) -> {
          process.send_exit(started.pid)
          Error(actor.InitFailed(
            "kairos root supervisor name already registered",
          ))
        }
      }
    }

    Error(error) -> Error(error)
  }
}
