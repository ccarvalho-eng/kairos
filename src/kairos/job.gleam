//// Core job domain types for Kairos.
////
//// This module defines the public types used to describe job state and
//// enqueue configuration.

/// The states a job can move through during its lifecycle.
pub type JobState {
  Pending
  Scheduled
  Executing
  Retryable
  Completed
  Discarded
  Cancelled
}

/// The scheduling strategy for a job.
pub type Schedule {
  Immediately
}

/// The enqueue options for a job definition or enqueue request.
pub opaque type EnqueueOptions {
  EnqueueOptions(
    queue: String,
    max_attempts: Int,
    priority: Int,
    schedule: Schedule,
  )
}

/// Returns the default enqueue options.
pub fn default_enqueue_options() -> EnqueueOptions {
  EnqueueOptions(
    queue: "default",
    max_attempts: 20,
    priority: 0,
    schedule: Immediately,
  )
}

/// Returns the configured queue name.
pub fn queue(options: EnqueueOptions) -> String {
  let EnqueueOptions(queue:, ..) = options
  queue
}

/// Returns the configured maximum number of attempts.
pub fn max_attempts(options: EnqueueOptions) -> Int {
  let EnqueueOptions(max_attempts:, ..) = options
  max_attempts
}

/// Returns the configured priority.
pub fn priority(options: EnqueueOptions) -> Int {
  let EnqueueOptions(priority:, ..) = options
  priority
}

/// Returns the configured scheduling strategy.
pub fn schedule(options: EnqueueOptions) -> Schedule {
  let EnqueueOptions(schedule:, ..) = options
  schedule
}
