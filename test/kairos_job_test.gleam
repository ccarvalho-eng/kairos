import gleeunit
import kairos/job

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn default_enqueue_options_test() {
  let options = job.default_enqueue_options()

  assert job.queue(options) == "default"
  assert job.max_attempts(options) == 20
  assert job.priority(options) == 0
  assert job.schedule(options) == job.Immediately
}

pub fn job_state_variants_test() {
  assert state_name(job.Pending) == "pending"
  assert state_name(job.Scheduled) == "scheduled"
  assert state_name(job.Executing) == "executing"
  assert state_name(job.Retryable) == "retryable"
  assert state_name(job.Completed) == "completed"
  assert state_name(job.Discarded) == "discarded"
  assert state_name(job.Cancelled) == "cancelled"
}

fn state_name(state: job.JobState) -> String {
  case state {
    job.Pending -> "pending"
    job.Scheduled -> "scheduled"
    job.Executing -> "executing"
    job.Retryable -> "retryable"
    job.Completed -> "completed"
    job.Discarded -> "discarded"
    job.Cancelled -> "cancelled"
  }
}
