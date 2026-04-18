import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import kairos/config
import kairos/supervision as kairos_supervision

pub fn package_name() -> String {
  "kairos"
}

pub fn start(
  config: config.Config,
) -> Result(actor.Started(kairos_supervision.Runtime), actor.StartError) {
  kairos_supervision.start(config: config)
}

pub fn supervised(
  config: config.Config,
) -> ChildSpecification(kairos_supervision.Runtime) {
  kairos_supervision.supervised(config: config)
}
