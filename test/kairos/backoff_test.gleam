import gleam/string
import gleeunit
import kairos/backoff

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn default_policy_uses_exponential_backoff_test() {
  let context =
    backoff.new_context(
      attempt: 3,
      max_attempts: 20,
      worker_name: "workers.example",
      queue_name: "default",
      error: "boom",
    )

  assert backoff.seconds(backoff.default_policy(), context) == 23
}

pub fn default_policy_handles_first_attempt_test() {
  let context =
    backoff.new_context(
      attempt: 1,
      max_attempts: 20,
      worker_name: "workers.example",
      queue_name: "default",
      error: "boom",
    )

  assert backoff.seconds(backoff.default_policy(), context) == 17
}

pub fn default_policy_handles_single_attempt_jobs_test() {
  let context =
    backoff.new_context(
      attempt: 1,
      max_attempts: 1,
      worker_name: "workers.example",
      queue_name: "default",
      error: "boom",
    )

  assert backoff.seconds(backoff.default_policy(), context) == 17
}

pub fn default_policy_clamps_large_attempt_ranges_test() {
  let context =
    backoff.new_context(
      attempt: 40,
      max_attempts: 100,
      worker_name: "workers.example",
      queue_name: "default",
      error: "boom",
    )

  assert backoff.seconds(backoff.default_policy(), context) == 271
}

pub fn custom_policy_receives_typed_retry_context_test() {
  let context =
    backoff.new_context(
      attempt: 4,
      max_attempts: 9,
      worker_name: "workers.mailers",
      queue_name: "mailers",
      error: "retry later",
    )
  let policy =
    backoff.custom_policy(fn(context) {
      backoff.attempt(context)
      + backoff.max_attempts(context)
      + string.length(backoff.worker_name(context))
      + string.length(backoff.queue_name(context))
      + string.length(backoff.error(context))
    })

  assert backoff.seconds(policy, context) == 46
}
