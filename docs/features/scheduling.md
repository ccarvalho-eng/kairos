# Scheduling

Use scheduling when a job should not run immediately.

## Schedule A Job

Build a scheduled option and pass it to `kairos.enqueue_with(...)`.

```gleam
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import kairos
import kairos/job

pub fn enqueue_report_for_later(
  kairos_config: config.Config,
) -> Result(job.EnqueuedJob(ReportArgs), kairos.EnqueueError) {
  let run_at = timestamp.add(timestamp.system_time(), duration.minutes(10))

  let assert Ok(options) =
    job.default_enqueue_options()
    |> job.with_queue("mailers")
    |> result.then(fn(options) { job.with_max_attempts(options, 3) })
    |> result.map(fn(options) { job.with_schedule(options, job.At(run_at)) })

  kairos.enqueue_with(
    kairos_config,
    report_worker(),
    ReportArgs(account_id: "acct_789"),
    options,
  )
}
```

## What Happens At Runtime

Scheduled jobs:

- are persisted immediately
- stay out of the runnable set until `scheduled_at <= now`
- are then claimed by the queue poller like any other runnable job

## Priority Still Applies

If several scheduled jobs become runnable together, Kairos prefers:

1. higher priority first
2. earlier `scheduled_at`
3. earlier `inserted_at`

That ordering is enforced in the claim query, not left implicit in application code.
