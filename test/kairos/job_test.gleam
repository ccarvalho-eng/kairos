import gleam/time/duration
import gleam/time/timestamp
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

pub fn enqueue_options_can_be_updated_test() {
  let now = timestamp.system_time()
  let scheduled_at = timestamp.add(now, duration.minutes(15))
  let assert Ok(queued) =
    job.with_queue(job.default_enqueue_options(), "mailers")
  let assert Ok(retrying) = job.with_max_attempts(queued, 5)
  let prioritized = job.with_priority(retrying, 9)
  let scheduled = job.with_schedule(prioritized, job.At(scheduled_at))

  assert job.queue(scheduled) == "mailers"
  assert job.max_attempts(scheduled) == 5
  assert job.priority(scheduled) == 9
  assert job.schedule(scheduled) == job.At(scheduled_at)
}

pub fn enqueue_options_reject_invalid_values_test() {
  assert job.with_queue(job.default_enqueue_options(), "   ")
    == Error(job.BlankQueueName)
  assert job.with_max_attempts(job.default_enqueue_options(), 0)
    == Error(job.NonPositiveMaxAttempts)
}
