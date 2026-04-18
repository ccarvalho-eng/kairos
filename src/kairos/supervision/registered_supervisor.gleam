import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/static_supervisor

@internal
pub fn start(
  name: process.Name(Nil),
  builder: static_supervisor.Builder,
  error_message: String,
) -> Result(actor.Started(static_supervisor.Supervisor), actor.StartError) {
  case static_supervisor.start(builder) {
    Ok(started) -> {
      case process.register(started.pid, name) {
        Ok(Nil) -> Ok(started)
        Error(_) -> {
          process.send_exit(started.pid)
          Error(actor.InitFailed(error_message))
        }
      }
    }

    Error(error) -> Error(error)
  }
}
