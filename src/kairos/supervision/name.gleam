import gleam/erlang/process
import gleam/string

@internal
pub fn root_supervisor() -> process.Name(Nil) {
  process.new_name("kairos-root")
}

@internal
pub fn queue_supervisor(queue_name: String) -> process.Name(Nil) {
  process.new_name("kairos-queue-" <> sanitize(queue_name))
}

@internal
pub fn queue_worker(queue_name: String) -> process.Name(Nil) {
  process.new_name("kairos-queue-worker-" <> sanitize(queue_name))
}

@internal
pub fn queue_poller(queue_name: String) -> process.Name(Nil) {
  process.new_name("kairos-queue-poller-" <> sanitize(queue_name))
}

fn sanitize(name: String) -> String {
  name
  |> string.lowercase
  |> string.replace(" ", "-")
  |> string.replace("/", "-")
}
