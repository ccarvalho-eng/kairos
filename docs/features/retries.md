# Retries And Backoff

Kairos retries jobs when a worker returns `worker.Retry(reason)`.

Retry behavior has two parts:

- how many attempts a job is allowed to make
- how long Kairos waits before retrying

## Set Max Attempts

You can set max attempts in worker defaults:

```gleam
import gleam/result
import kairos/job

pub fn report_worker_options() -> job.EnqueueOptions {
  let assert Ok(options) =
    job.default_enqueue_options()
    |> job.with_queue("default")
    |> result.then(fn(options) { job.with_max_attempts(options, 5) })

  options
}
```

Or override max attempts for one specific enqueue call with `enqueue_with(...)`.

## Attach A Backoff Policy

Backoff is configured on the worker itself with `worker.with_backoff(...)`.

```gleam
import kairos/backoff
import kairos/worker

pub fn report_worker() -> worker.Worker(ReportArgs) {
  worker.new(
    "workers.daily_report",
    fn(args) {
      let ReportArgs(account_id:) = args
      account_id
    },
    fn(payload) { Ok(ReportArgs(account_id: payload)) },
    fn(_args) { worker.Retry("temporary upstream failure") },
    report_worker_options(),
  )
  |> worker.with_backoff(backoff.constant_policy(30))
}
```

You can also build a custom policy:

```gleam
import kairos/backoff

pub fn custom_report_backoff() -> backoff.Policy {
  backoff.custom_policy(fn(context) {
    case backoff.attempt(context) <= 3 {
      True -> 15
      False -> 60
    }
  })
}
```

## What Happens When Retries Run Out

When `attempt >= max_attempts`, the job is no longer runnable.
Further failures move it into a terminal discarded state instead of retrying forever.
