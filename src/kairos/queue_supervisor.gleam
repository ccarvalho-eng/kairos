import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import kairos/config
import kairos/queue_stub
import kairos/supervision/registered_supervisor

pub opaque type Runtime {
  Runtime(
    name: String,
    supervisor_name: process.Name(Nil),
    worker_name: process.Name(Nil),
    poller_name: process.Name(Nil),
  )
}

pub fn from_queue(queue: config.Queue) -> Runtime {
  Runtime(
    name: config.queue_name(queue),
    supervisor_name: config.queue_supervisor_name(queue),
    worker_name: config.queue_worker_name(queue),
    poller_name: config.queue_poller_name(queue),
  )
}

pub fn start(
  queue queue: config.Queue,
) -> Result(actor.Started(Runtime), actor.StartError) {
  let runtime = from_queue(queue)
  let Runtime(
    supervisor_name: supervisor_name,
    worker_name: worker_name,
    poller_name: poller_name,
    ..,
  ) = runtime
  let builder =
    static_supervisor.new(static_supervisor.OneForAll)
    |> static_supervisor.add(queue_stub.supervised(name: worker_name))
    |> static_supervisor.add(queue_stub.supervised(name: poller_name))

  case
    registered_supervisor.start(
      supervisor_name,
      builder,
      "queue supervisor name already registered",
    )
  {
    Ok(started) -> Ok(actor.Started(pid: started.pid, data: runtime))
    Error(error) -> Error(error)
  }
}

pub fn supervised(queue queue: config.Queue) -> ChildSpecification(Runtime) {
  supervision.supervisor(fn() { start(queue: queue) })
}

pub fn name(runtime: Runtime) -> String {
  let Runtime(name:, ..) = runtime
  name
}

pub fn supervisor_pid(runtime: Runtime) -> Result(process.Pid, Nil) {
  let Runtime(supervisor_name:, ..) = runtime
  process.named(supervisor_name)
}

pub fn worker_pid(runtime: Runtime) -> Result(process.Pid, Nil) {
  let Runtime(worker_name:, ..) = runtime
  process.named(worker_name)
}

pub fn poller_pid(runtime: Runtime) -> Result(process.Pid, Nil) {
  let Runtime(poller_name:, ..) = runtime
  process.named(poller_name)
}
