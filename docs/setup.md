# Setup

This guide walks through the baseline host-application setup on the current `main` branch.

If you want feature-specific examples after setup, continue with:

- [`docs/features/README.md`](./features/README.md)
- [`docs/features/enqueueing.md`](./features/enqueueing.md)
- [`docs/features/scheduling.md`](./features/scheduling.md)
- [`docs/features/retries.md`](./features/retries.md)
- [`docs/features/cancellation.md`](./features/cancellation.md)
- [`docs/features/recovery.md`](./features/recovery.md)

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

## 3. Define A Queue

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

## 4. Define A Worker In Your App

Create workers in your host application before you build `config.Config`.
Kairos does not generate workers for you.

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

This worker value is reused in two places:

1. registration inside `config.Config`
2. enqueue calls like `kairos.enqueue(...)`

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
  let assert Ok(default_queue_definition) = default_queue()

  config.new(
    connection: connection,
    queues: [default_queue_definition],
    workers: [worker.register(report_worker())],
  )
}
```

This is the point where Kairos learns which workers your application supports.

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
- dispatch claimed jobs through supervised runners
- persist lifecycle transitions back to PostgreSQL

## 7. Minimal End-To-End Shape

This is the smallest setup for one queue and one worker:

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

## 8. Next Steps

After the baseline setup, use the feature guides for concrete workflows:

- [`enqueueing.md`](./features/enqueueing.md)
- [`scheduling.md`](./features/scheduling.md)
- [`retries.md`](./features/retries.md)
- [`cancellation.md`](./features/cancellation.md)
- [`recovery.md`](./features/recovery.md)

## 9. Local Development Checklist

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
