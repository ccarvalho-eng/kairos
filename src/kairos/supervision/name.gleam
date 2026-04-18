import gleam/erlang/process
import gleam/otp/factory_supervisor
import gleam/string
import kairos/job_runner
import kairos/queue_poller
import kairos/queue_reaper

@internal
pub fn root_supervisor() -> process.Name(Nil) {
  process.new_name("kairos-root")
}

@internal
pub fn queue_supervisor(queue_name: String) -> process.Name(Nil) {
  process.new_name("kairos-queue-" <> sanitize(queue_name))
}

@internal
pub fn queue_runner_supervisor(
  queue_name: String,
) -> process.Name(factory_supervisor.Message(job_runner.RunnerArg, String)) {
  process.new_name("kairos-queue-runner-" <> sanitize(queue_name))
}

@internal
pub fn queue_poller(queue_name: String) -> process.Name(queue_poller.Message) {
  process.new_name("kairos-queue-poller-" <> sanitize(queue_name))
}

@internal
pub fn queue_reaper(queue_name: String) -> process.Name(queue_reaper.Message) {
  process.new_name("kairos-queue-reaper-" <> sanitize(queue_name))
}

fn sanitize(name: String) -> String {
  name
  |> string.lowercase
  |> string.replace(" ", "-")
  |> string.replace("/", "-")
}
