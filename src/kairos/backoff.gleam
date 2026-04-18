import gleam/float
import gleam/int

pub opaque type Policy {
  Policy(apply: fn(Context) -> Int)
}

pub opaque type Context {
  Context(
    attempt: Int,
    max_attempts: Int,
    worker_name: String,
    queue_name: String,
    error: String,
  )
}

pub fn new_context(
  attempt attempt: Int,
  max_attempts max_attempts: Int,
  worker_name worker_name: String,
  queue_name queue_name: String,
  error error: String,
) -> Context {
  Context(
    attempt: attempt,
    max_attempts: max_attempts,
    worker_name: worker_name,
    queue_name: queue_name,
    error: error,
  )
}

pub fn attempt(context: Context) -> Int {
  let Context(attempt:, ..) = context
  attempt
}

pub fn max_attempts(context: Context) -> Int {
  let Context(max_attempts:, ..) = context
  max_attempts
}

pub fn worker_name(context: Context) -> String {
  let Context(worker_name:, ..) = context
  worker_name
}

pub fn queue_name(context: Context) -> String {
  let Context(queue_name:, ..) = context
  queue_name
}

pub fn error(context: Context) -> String {
  let Context(error:, ..) = context
  error
}

pub fn default_policy() -> Policy {
  custom_policy(default_seconds)
}

pub fn constant_policy(seconds: Int) -> Policy {
  custom_policy(fn(_) { seconds })
}

pub fn custom_policy(apply: fn(Context) -> Int) -> Policy {
  Policy(fn(context) {
    let seconds = apply(context)
    int.max(seconds, 0)
  })
}

pub fn seconds(policy: Policy, context: Context) -> Int {
  let Policy(apply:) = policy
  apply(context)
}

fn default_seconds(context: Context) -> Int {
  let clamped_attempt = case max_attempts(context) <= 20 {
    True -> attempt(context)
    False ->
      float.round(
        int.to_float(attempt(context))
        /. int.to_float(max_attempts(context))
        *. 20.0,
      )
  }

  15 + pow2(int.min(clamped_attempt, 20))
}

fn pow2(exponent: Int) -> Int {
  case exponent <= 0 {
    True -> 1
    False -> 2 * pow2(exponent - 1)
  }
}
