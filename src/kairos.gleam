import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import kairos/config
import kairos/runtime

pub fn package_name() -> String {
  "kairos"
}

pub fn start(
  config: config.Config,
) -> Result(actor.Started(runtime.Runtime), actor.StartError) {
  runtime.start(config: config)
}

pub fn supervised(config: config.Config) -> ChildSpecification(runtime.Runtime) {
  runtime.supervised(config: config)
}
