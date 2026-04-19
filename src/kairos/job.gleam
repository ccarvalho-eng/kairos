//// Core job domain types for Kairos.
////
//// This module defines the public types used to describe job state and
//// enqueue configuration.

import gleam/option.{type Option}
import gleam/string
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

pub type EnqueueOptionError {
  BlankQueueName
  NonPositiveMaxAttempts
}

pub opaque type EnqueueOptions {
  EnqueueOptions(
    queue: String,
    max_attempts: Int,
    priority: Int,
    schedule: Schedule,
  )
}

pub type EnqueuedJob(args) {
  EnqueuedJob(
    id: String,
    worker_name: String,
    args: args,
    state: JobState,
    queue_name: String,
    priority: Int,
    attempt: Int,
    max_attempts: Int,
    unique_key: Option(String),
    errors: List(String),
    scheduled_at: timestamp.Timestamp,
    attempted_at: Option(timestamp.Timestamp),
    completed_at: Option(timestamp.Timestamp),
    discarded_at: Option(timestamp.Timestamp),
    cancelled_at: Option(timestamp.Timestamp),
    inserted_at: timestamp.Timestamp,
    updated_at: timestamp.Timestamp,
  )
}

pub type JobSnapshot {
  JobSnapshot(
    id: String,
    worker_name: String,
    payload: String,
    state: JobState,
    queue_name: String,
    priority: Int,
    attempt: Int,
    max_attempts: Int,
    unique_key: Option(String),
    errors: List(String),
    scheduled_at: timestamp.Timestamp,
    attempted_at: Option(timestamp.Timestamp),
    completed_at: Option(timestamp.Timestamp),
    discarded_at: Option(timestamp.Timestamp),
    cancelled_at: Option(timestamp.Timestamp),
    inserted_at: timestamp.Timestamp,
    updated_at: timestamp.Timestamp,
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

pub fn with_queue(
  options: EnqueueOptions,
  queue: String,
) -> Result(EnqueueOptions, EnqueueOptionError) {
  case string.trim(queue) {
    "" -> Error(BlankQueueName)
    trimmed_queue -> {
      let EnqueueOptions(max_attempts:, priority:, schedule:, ..) = options

      Ok(EnqueueOptions(
        queue: trimmed_queue,
        max_attempts: max_attempts,
        priority: priority,
        schedule: schedule,
      ))
    }
  }
}

pub fn max_attempts(options: EnqueueOptions) -> Int {
  let EnqueueOptions(max_attempts:, ..) = options
  max_attempts
}

pub fn with_max_attempts(
  options: EnqueueOptions,
  max_attempts: Int,
) -> Result(EnqueueOptions, EnqueueOptionError) {
  case max_attempts <= 0 {
    True -> Error(NonPositiveMaxAttempts)
    False -> {
      let EnqueueOptions(queue:, priority:, schedule:, ..) = options

      Ok(EnqueueOptions(
        queue: queue,
        max_attempts: max_attempts,
        priority: priority,
        schedule: schedule,
      ))
    }
  }
}

pub fn priority(options: EnqueueOptions) -> Int {
  let EnqueueOptions(priority:, ..) = options
  priority
}

pub fn with_priority(options: EnqueueOptions, priority: Int) -> EnqueueOptions {
  let EnqueueOptions(queue:, max_attempts:, schedule:, ..) = options

  EnqueueOptions(
    queue: queue,
    max_attempts: max_attempts,
    priority: priority,
    schedule: schedule,
  )
}

pub fn schedule(options: EnqueueOptions) -> Schedule {
  let EnqueueOptions(schedule:, ..) = options
  schedule
}

pub fn with_schedule(
  options: EnqueueOptions,
  schedule: Schedule,
) -> EnqueueOptions {
  let EnqueueOptions(queue:, max_attempts:, priority:, ..) = options

  EnqueueOptions(
    queue: queue,
    max_attempts: max_attempts,
    priority: priority,
    schedule: schedule,
  )
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
