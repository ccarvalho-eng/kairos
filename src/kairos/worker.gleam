//// Typed worker contracts for Kairos jobs.
////
//// Worker definitions in this module encode typed arguments into a persisted
//// string payload and decode them again before execution.

import exception
import gleam/string
import kairos/backoff
import kairos/job

pub type DecodeError {
  DecodeError(String)
}

pub type PerformResult {
  Success
  Retry(String)
  Discard(String)
  Cancel(String)
}

pub type PayloadExecutionResult {
  Succeeded
  RetryRequested(String)
  DiscardRequested(String)
  CancelRequested(String)
  DecodeFailed(String)
  Crashed(String)
}

pub opaque type Worker(args) {
  Worker(
    name: String,
    encoder: fn(args) -> String,
    decoder: fn(String) -> Result(args, DecodeError),
    performer: fn(args) -> PerformResult,
    default_options: job.EnqueueOptions,
    backoff_policy: backoff.Policy,
  )
}

pub opaque type RegisteredWorker {
  RegisteredWorker(
    name: String,
    execute_payload: fn(String) -> PayloadExecutionResult,
    backoff_seconds: fn(backoff.Context) -> Int,
  )
}

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
    backoff_policy: backoff.default_policy(),
  )
}

pub fn name(contract: Worker(args)) -> String {
  let Worker(name:, ..) = contract
  name
}

pub fn default_options(contract: Worker(args)) -> job.EnqueueOptions {
  let Worker(default_options:, ..) = contract
  default_options
}

pub fn with_backoff(
  contract: Worker(args),
  policy: backoff.Policy,
) -> Worker(args) {
  let Worker(name:, encoder:, decoder:, performer:, default_options:, ..) =
    contract

  Worker(
    name: name,
    encoder: encoder,
    decoder: decoder,
    performer: performer,
    default_options: default_options,
    backoff_policy: policy,
  )
}

/// Encodes worker arguments into a persisted payload string.
pub fn encode(contract: Worker(args), args: args) -> String {
  let Worker(encoder:, ..) = contract
  encoder(args)
}

/// Decodes a persisted payload string into worker arguments.
pub fn decode(
  contract: Worker(args),
  payload: String,
) -> Result(args, DecodeError) {
  let Worker(decoder:, ..) = contract
  decoder(payload)
}

pub fn perform(contract: Worker(args), args: args) -> PerformResult {
  let Worker(performer:, ..) = contract
  performer(args)
}

pub fn register(contract: Worker(args)) -> RegisteredWorker {
  let Worker(backoff_policy:, ..) = contract

  RegisteredWorker(
    name: name(contract),
    execute_payload: fn(payload) { run_payload(contract, payload) },
    backoff_seconds: fn(context) { backoff.seconds(backoff_policy, context) },
  )
}

pub fn registered_name(registered_worker: RegisteredWorker) -> String {
  let RegisteredWorker(name:, ..) = registered_worker
  name
}

@internal
pub fn execute_payload(
  registered_worker: RegisteredWorker,
  payload: String,
) -> PayloadExecutionResult {
  let RegisteredWorker(execute_payload:, ..) = registered_worker
  execute_payload(payload)
}

@internal
pub fn backoff_seconds(
  registered_worker: RegisteredWorker,
  context: backoff.Context,
) -> Int {
  let RegisteredWorker(backoff_seconds:, ..) = registered_worker
  backoff_seconds(context)
}

fn run_payload(
  contract: Worker(args),
  payload: String,
) -> PayloadExecutionResult {
  case
    exception.rescue(fn() {
      case decode(contract, payload) {
        Ok(args) -> Ok(perform(contract, args))
        Error(DecodeError(reason)) -> Error(DecodeFailed(reason))
      }
    })
  {
    Ok(Ok(result)) -> map_perform_result(result)
    Ok(Error(decode_error)) -> decode_error
    Error(error) -> Crashed(format_exception(error))
  }
}

fn map_perform_result(result: PerformResult) -> PayloadExecutionResult {
  case result {
    Success -> Succeeded
    Retry(reason) -> RetryRequested(reason)
    Discard(reason) -> DiscardRequested(reason)
    Cancel(reason) -> CancelRequested(reason)
  }
}

fn format_exception(error: exception.Exception) -> String {
  case error {
    exception.Errored(dynamic) -> "errored: " <> string.inspect(dynamic)
    exception.Thrown(dynamic) -> "thrown: " <> string.inspect(dynamic)
    exception.Exited(dynamic) -> "exited: " <> string.inspect(dynamic)
  }
}
