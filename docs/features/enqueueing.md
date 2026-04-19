# Enqueueing

Kairos has two enqueue entry points:

- `kairos.enqueue(...)`
- `kairos.enqueue_with(...)`

Use `enqueue(...)` when the worker defaults are enough.
Use `enqueue_with(...)` when you want to override options for one job.

## Worker Defaults

Each worker carries default enqueue options.

```gleam
import gleam/result
import kairos/job
import kairos/worker

type ReportArgs {
  ReportArgs(account_id: String)
}

pub fn report_worker_options() -> job.EnqueueOptions {
  let assert Ok(options) =
    job.default_enqueue_options()
    |> job.with_queue("mailers")
    |> result.then(fn(options) { job.with_max_attempts(options, 5) })

  job.with_priority(options, 10)
}

pub fn report_worker() -> worker.Worker(ReportArgs) {
  worker.new(
    "workers.daily_report",
    fn(args) {
      let ReportArgs(account_id:) = args
      account_id
    },
    fn(payload) { Ok(ReportArgs(account_id: payload)) },
    fn(_args) { worker.Success },
    report_worker_options(),
  )
}
```

Those defaults are used by `kairos.enqueue(...)`.

## Enqueue With Worker Defaults

```gleam
import kairos

pub fn enqueue_report(
  kairos_config: config.Config,
) -> Result(job.EnqueuedJob(ReportArgs), kairos.EnqueueError) {
  kairos.enqueue(
    kairos_config,
    report_worker(),
    ReportArgs(account_id: "acct_123"),
  )
}
```

## Override Options For One Job

Use `enqueue_with(...)` when you want to change:

- queue
- max attempts
- priority
- schedule

for one specific enqueue call.

```gleam
import gleam/result
import kairos
import kairos/job

pub fn enqueue_report_to_critical_queue(
  kairos_config: config.Config,
) -> Result(job.EnqueuedJob(ReportArgs), kairos.EnqueueError) {
  let assert Ok(options) =
    job.default_enqueue_options()
    |> job.with_queue("critical")
    |> result.then(fn(options) { job.with_max_attempts(options, 3) })

  kairos.enqueue_with(
    kairos_config,
    report_worker(),
    ReportArgs(account_id: "acct_456"),
    job.with_priority(options, 20),
  )
}
```

## What To Remember

- worker defaults live on the worker definition
- per-job overrides happen in `enqueue_with(...)`
- the worker you enqueue must already be registered in `config.Config`
