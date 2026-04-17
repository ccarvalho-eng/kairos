import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

pub fn start(
  name name: process.Name(Nil),
) -> Result(actor.Started(Nil), actor.StartError) {
  actor.new(Nil)
  |> actor.named(name)
  |> actor.start
  |> result.map(fn(started) { actor.Started(pid: started.pid, data: Nil) })
}

pub fn supervised(name name: process.Name(Nil)) -> ChildSpecification(Nil) {
  supervision.worker(fn() { start(name: name) })
}
