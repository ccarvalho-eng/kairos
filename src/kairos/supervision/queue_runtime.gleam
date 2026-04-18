import gleam/erlang/process
import gleam/otp/factory_supervisor
import kairos/queue
import kairos/runtime/job_runner
import kairos/runtime/queue_poller
import kairos/runtime/queue_reaper
import kairos/supervision/name

pub opaque type QueueRuntime {
  QueueRuntime(
    name: String,
    concurrency: Int,
    poll_interval_ms: Int,
    supervisor_name: process.Name(Nil),
    runner_supervisor_name: process.Name(
      factory_supervisor.Message(job_runner.RunnerArg, String),
    ),
    poller_name: process.Name(queue_poller.Message),
    reaper_name: process.Name(queue_reaper.Message),
  )
}

@internal
pub fn from_queue(queue_definition: queue.Queue) -> QueueRuntime {
  let queue_name = queue.name(queue_definition)

  QueueRuntime(
    name: queue_name,
    concurrency: queue.concurrency(queue_definition),
    poll_interval_ms: queue.poll_interval_ms(queue_definition),
    supervisor_name: name.queue_supervisor(queue_name),
    runner_supervisor_name: name.queue_runner_supervisor(queue_name),
    poller_name: name.queue_poller(queue_name),
    reaper_name: name.queue_reaper(queue_name),
  )
}

pub fn name(runtime: QueueRuntime) -> String {
  let QueueRuntime(name:, ..) = runtime
  name
}

@internal
pub fn concurrency(runtime: QueueRuntime) -> Int {
  let QueueRuntime(concurrency:, ..) = runtime
  concurrency
}

@internal
pub fn poll_interval_ms(runtime: QueueRuntime) -> Int {
  let QueueRuntime(poll_interval_ms:, ..) = runtime
  poll_interval_ms
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
pub fn poller_name(runtime: QueueRuntime) -> process.Name(queue_poller.Message) {
  let QueueRuntime(poller_name:, ..) = runtime
  poller_name
}

@internal
pub fn reaper_name(runtime: QueueRuntime) -> process.Name(queue_reaper.Message) {
  let QueueRuntime(reaper_name:, ..) = runtime
  reaper_name
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

@internal
pub fn reaper_pid(runtime: QueueRuntime) -> Result(process.Pid, Nil) {
  process.named(reaper_name(runtime))
}
