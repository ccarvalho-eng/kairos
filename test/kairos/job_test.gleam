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

pub fn job_state_round_trip_test() {
  assert job.state_name(job.Pending) == "pending"
  assert job.state_name(job.Scheduled) == "scheduled"
  assert job.state_name(job.Executing) == "executing"
  assert job.state_name(job.Retryable) == "retryable"
  assert job.state_name(job.Completed) == "completed"
  assert job.state_name(job.Discarded) == "discarded"
  assert job.state_name(job.Cancelled) == "cancelled"
  assert job.state_from_string("pending") == Ok(job.Pending)
  assert job.state_from_string("scheduled") == Ok(job.Scheduled)
  assert job.state_from_string("executing") == Ok(job.Executing)
  assert job.state_from_string("retryable") == Ok(job.Retryable)
  assert job.state_from_string("completed") == Ok(job.Completed)
  assert job.state_from_string("discarded") == Ok(job.Discarded)
  assert job.state_from_string("cancelled") == Ok(job.Cancelled)
  assert job.state_from_string("unknown") == Error(Nil)
}
