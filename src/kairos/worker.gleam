//// Typed worker contracts for Kairos jobs.
////
//// Worker definitions in this module encode typed arguments into a durable
//// string payload and decode them again before execution.

import kairos/job

/// An error returned when a payload cannot be decoded.
pub type DecodeError {
  DecodeError(String)
}

/// The result of executing a job.
pub type PerformResult {
  Success
  Retry(String)
  Discard(String)
  Cancel(String)
}

/// A typed worker definition.
pub opaque type Worker(args) {
  Worker(
    name: String,
    encoder: fn(args) -> String,
    decoder: fn(String) -> Result(args, DecodeError),
    performer: fn(args) -> PerformResult,
    default_options: job.EnqueueOptions,
  )
}

/// Creates a new worker definition.
pub fn new(
  name: String,
  encoder: fn(args) -> String,
  decoder: fn(String) -> Result(args, DecodeError),
  performer: fn(args) -> PerformResult,
  default_options: job.EnqueueOptions,
) -> Worker(args) {
  Worker(
    name: name,
    encoder: encoder,
    decoder: decoder,
    performer: performer,
    default_options: default_options,
  )
}

/// Returns the worker name.
pub fn name(contract: Worker(args)) -> String {
  let Worker(name:, ..) = contract
  name
}

/// Returns the worker's default enqueue options.
pub fn default_options(contract: Worker(args)) -> job.EnqueueOptions {
  let Worker(default_options:, ..) = contract
  default_options
}

/// Encodes worker arguments into a durable payload string.
pub fn encode(contract: Worker(args), args: args) -> String {
  let Worker(encoder:, ..) = contract
  encoder(args)
}

/// Decodes a durable payload string into worker arguments.
pub fn decode(
  contract: Worker(args),
  payload: String,
) -> Result(args, DecodeError) {
  let Worker(decoder:, ..) = contract
  decoder(payload)
}

/// Executes the worker with typed arguments.
pub fn perform(contract: Worker(args), args: args) -> PerformResult {
  let Worker(performer:, ..) = contract
  performer(args)
}
