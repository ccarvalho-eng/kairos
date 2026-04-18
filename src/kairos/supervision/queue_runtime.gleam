import gleam/erlang/process
import gleam/otp/factory_supervisor
import kairos/job_runner
import kairos/queue
import kairos/supervision/name

pub opaque type QueueRuntime {
  QueueRuntime(
    name: String,
    supervisor_name: process.Name(Nil),
    runner_supervisor_name: process.Name(
      factory_supervisor.Message(job_runner.RunnerArg, String),
    ),
    poller_name: process.Name(Nil),
  )
}

@internal
pub fn from_queue(queue_definition: queue.Queue) -> QueueRuntime {
  let queue_name = queue.name(queue_definition)

  QueueRuntime(
    name: queue_name,
    supervisor_name: name.queue_supervisor(queue_name),
    runner_supervisor_name: name.queue_runner_supervisor(queue_name),
    poller_name: name.queue_poller(queue_name),
  )
}

pub fn name(runtime: QueueRuntime) -> String {
  let QueueRuntime(name:, ..) = runtime
  name
}

@internal
pub fn supervisor_name(runtime: QueueRuntime) -> process.Name(Nil) {
  let QueueRuntime(supervisor_name:, ..) = runtime
  supervisor_name
}

@internal
pub fn runner_supervisor_name(
  runtime: QueueRuntime,
) -> process.Name(factory_supervisor.Message(job_runner.RunnerArg, String)) {
  let QueueRuntime(runner_supervisor_name:, ..) = runtime
  runner_supervisor_name
}

@internal
pub fn poller_name(runtime: QueueRuntime) -> process.Name(Nil) {
  let QueueRuntime(poller_name:, ..) = runtime
  poller_name
}

@internal
pub fn supervisor_pid(runtime: QueueRuntime) -> Result(process.Pid, Nil) {
  process.named(supervisor_name(runtime))
}

@internal
pub fn runner_supervisor_pid(runtime: QueueRuntime) -> Result(process.Pid, Nil) {
  process.named(runner_supervisor_name(runtime))
}

@internal
pub fn poller_pid(runtime: QueueRuntime) -> Result(process.Pid, Nil) {
  process.named(poller_name(runtime))
}
