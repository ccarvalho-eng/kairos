//// Core job domain types for Kairos.
////
//// This module defines the public types used to describe job state and
//// enqueue configuration.

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
