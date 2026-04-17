import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

pub fn start(
  name name: process.Name(Nil),
) -> Result(actor.Started(Nil), actor.StartError) {
  case actor.new(Nil) |> actor.named(name) |> actor.start {
    Ok(started) -> Ok(actor.Started(pid: started.pid, data: Nil))
    Error(error) -> Error(error)
  }
}

pub fn supervised(name name: process.Name(Nil)) -> ChildSpecification(Nil) {
  supervision.worker(fn() { start(name: name) })
}
