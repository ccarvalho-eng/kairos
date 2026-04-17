//// Core job domain types for Kairos.
////
//// This module defines the public types used to describe job state and
//// enqueue configuration.

import gleam/time/timestamp

pub type JobState {
  Pending
  Scheduled
  Executing
  Retryable
  Completed
  Discarded
  Cancelled
}

pub type Schedule {
  Immediately
  At(timestamp.Timestamp)
}

pub opaque type EnqueueOptions {
  EnqueueOptions(
    queue: String,
    max_attempts: Int,
    priority: Int,
    schedule: Schedule,
  )
}

pub fn default_enqueue_options() -> EnqueueOptions {
  EnqueueOptions(
    queue: "default",
    max_attempts: 20,
    priority: 0,
    schedule: Immediately,
  )
}

pub fn queue(options: EnqueueOptions) -> String {
  let EnqueueOptions(queue:, ..) = options
  queue
}

pub fn max_attempts(options: EnqueueOptions) -> Int {
  let EnqueueOptions(max_attempts:, ..) = options
  max_attempts
}

pub fn priority(options: EnqueueOptions) -> Int {
  let EnqueueOptions(priority:, ..) = options
  priority
}

pub fn schedule(options: EnqueueOptions) -> Schedule {
  let EnqueueOptions(schedule:, ..) = options
  schedule
}

pub fn state_name(state: JobState) -> String {
  case state {
    Pending -> "pending"
    Scheduled -> "scheduled"
    Executing -> "executing"
    Retryable -> "retryable"
    Completed -> "completed"
    Discarded -> "discarded"
    Cancelled -> "cancelled"
  }
}

pub fn state_from_string(state: String) -> Result(JobState, Nil) {
  case state {
    "pending" -> Ok(Pending)
    "scheduled" -> Ok(Scheduled)
    "executing" -> Ok(Executing)
    "retryable" -> Ok(Retryable)
    "completed" -> Ok(Completed)
    "discarded" -> Ok(Discarded)
    "cancelled" -> Ok(Cancelled)
    _ -> Error(Nil)
  }
}
