# Setup

This guide walks through a minimal host-application setup on the current `main` branch.

## 1. Start a PostgreSQL Pool

Kairos expects the host application to own PostgreSQL connection setup and supervision.

```gleam
import gleam/erlang/process
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import pog

pub fn database_pool(
  pool_name: process.Name(pog.Message),
  database_url: String,
) -> Result(ChildSpecification(pog.Connection), Nil) {
  use config <- result.try(pog.url_config(pool_name, database_url))
  Ok(pog.supervised(config))
}
```

## 2. Apply Migrations

Kairos exposes its schema as migration data through `kairos/migration`.

Your host application should run:

- `migration.migrations()`
- `migration.version(...)`
- `migration.name(...)`
- `migration.statements(...)`

against its existing migration runner.

## 3. Define Queues

At least one queue is required.

```gleam
import kairos/queue

pub fn default_queue() -> Result(queue.Queue, queue.QueueError) {
  queue.new(name: "default", concurrency: 10, poll_interval_ms: 1_000)
}
```

Queue settings mean:

- `name`: queue identity
- `concurrency`: maximum jobs claimed and started per poll cycle
- `poll_interval_ms`: how often the queue poller checks for runnable jobs

## 4. Define Workers In Your App

Create your workers in your host application before you build `config.Config`.
Kairos does not create worker modules for you. Your app defines them as normal Gleam functions or modules, then registers them in `config.Config` and reuses the same worker values when enqueueing jobs.

The order is:

1. define the worker contract in your app code
2. register that worker in `config.Config`
3. pass the same worker when calling `kairos.enqueue(...)`

Workers are typed contracts with explicit encode, decode, and perform behavior.
Each worker also carries a set of default enqueue options. Those defaults are used by `kairos.enqueue(...)`.

Use that when you want the worker itself to define its normal queueing behavior.

```gleam
import kairos/job
import kairos/worker

type ReportArgs {
  ReportArgs(account_id: String)
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
    job.default_enqueue_options(),
  )
}
```

If you want this worker to always start with custom defaults, build those options before `worker.new(...)`.

Use worker defaults for stable behavior that should apply every time this worker is enqueued, such as:

- the usual queue
- the usual max attempts
- the usual priority

Scheduling is usually a per-job concern, so it is clearer to override that at enqueue time instead of baking it into the worker defaults.

```gleam
import gleam/result
import kairos/job

pub fn report_worker_options() -> job.EnqueueOptions {
  let assert Ok(options) =
    job.default_enqueue_options()
    |> job.with_queue("mailers")
    |> result.then(fn(options) { job.with_max_attempts(options, 5) })

```gleam
  job.with_priority(options, 10)
}
```

Common option builders are:

- `job.with_queue(...)`
- `job.with_max_attempts(...)`
- `job.with_priority(...)`
- `job.with_schedule(...)`

## 5. Build `config.Config`

Register queues and workers in one runtime config value.

```gleam
import kairos/config
import kairos/queue
import kairos/worker
import pog

pub fn kairos_config(
  connection: pog.Connection,
) -> Result(config.Config, config.ConfigError) {
  let assert Ok(default_queue) =
    queue.new(name: "default", concurrency: 10, poll_interval_ms: 1_000)

  config.new(
    connection: connection,
    queues: [default_queue],
    workers: [worker.register(report_worker())],
  )
}
```

This is the point where Kairos learns which workers your application supports.
If a worker is not registered here, the runtime cannot execute persisted jobs for it.

## 6. Start Kairos Under Supervision

```gleam
import gleam/otp/supervision.{type ChildSpecification}
import kairos
import kairos/config
import kairos/supervision

pub fn kairos_child(
  kairos_config: config.Config,
) -> ChildSpecification(supervision.Runtime) {
  kairos.supervised(kairos_config)
}
```

Once started, Kairos will:

- poll each queue on its configured interval
- claim runnable jobs atomically
- dispatch claimed jobs through the queue runner supervisor
- persist completion, retry, discard, cancel, and stale-recovery transitions

## 7. Enqueue Work

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

Use `kairos.enqueue(...)` when the worker defaults are enough.

Use `kairos.enqueue_with(...)` when you want to override options for one specific job.

That is where you bypass the worker defaults for one enqueue call, including cases like:

- lower `max_attempts` for one job
- a different queue for one job
- a higher priority for one job
- a future schedule for one job

```gleam
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import kairos
import kairos/job

pub fn enqueue_report_with_overrides(
  kairos_config: config.Config,
) -> Result(job.EnqueuedJob(ReportArgs), kairos.EnqueueError) {
  let assert Ok(options) =
    job.default_enqueue_options()
    |> job.with_queue("mailers")
    |> result.then(fn(options) { job.with_max_attempts(options, 3) })
    |> result.map(fn(options) {
      options
        |> job.with_priority(20)
        |> job.with_schedule(
          job.At(timestamp.add(timestamp.system_time(), duration.minutes(10))),
        )
    })

  kairos.enqueue_with(
    kairos_config,
    report_worker(),
    ReportArgs(account_id: "acct_456"),
    options,
  )
}
```

The available per-job overrides are:

- queue
- max attempts
- priority
- schedule

The important connection is that `report_worker()` here is the same worker your app defined earlier and registered in `config.Config`.

## 8. Complete Minimal Example

This is the smallest end-to-end shape for one queue and one worker:

```gleam
import gleam/result
import kairos
import kairos/config
import kairos/job
import kairos/queue
import kairos/supervision
import kairos/worker
import pog

type ReportArgs {
  ReportArgs(account_id: String)
}

pub fn report_worker_options() -> job.EnqueueOptions {
  let assert Ok(options) =
    job.default_enqueue_options()
    |> job.with_queue("default")
    |> result.then(fn(options) { job.with_max_attempts(options, 5) })

  job.with_priority(options, 0)
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

pub fn default_queue() -> Result(queue.Queue, queue.QueueError) {
  queue.new(name: "default", concurrency: 10, poll_interval_ms: 1_000)
}

pub fn kairos_config(
  connection: pog.Connection,
) -> Result(config.Config, config.ConfigError) {
  let assert Ok(default_queue_definition) = default_queue()

  config.new(
    connection: connection,
    queues: [default_queue_definition],
    workers: [worker.register(report_worker())],
  )
}

pub fn kairos_child(
  kairos_config: config.Config,
) -> supervision.ChildSpecification(supervision.Runtime) {
  kairos.supervised(kairos_config)
}

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

## 9. Optional Operational APIs

Kairos currently exposes two operational helpers at the package boundary:

- `kairos.cancel(config, job_id)`
  Cancels jobs that have not started executing yet.
- `kairos.recover_stale(runtime, queue_name, now, stale_for)`
  Recovers stale `executing` jobs in bounded batches.

## 10. Local Development Checklist

```sh
gleam deps download
createdb kairos_test
export KAIROS_TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/kairos_test?sslmode=disable
gleam test
```

## Notes

- Kairos is still `0.x`, so the API and supervision model may keep moving.
- The current runtime is designed for a single node.
- The host application still owns installation, migrations, and PostgreSQL pool lifecycle.
