<div align="center">

<img width="80" alt="kairos-logo" src="https://github.com/user-attachments/assets/5f75f409-82ca-46f5-91c6-91ec4d4379a2" />

# Kairos

[![CI](https://github.com/ccarvalho-eng/kairos/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ccarvalho-eng/kairos/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](./LICENSE)

Typed background jobs for Gleam on the BEAM.

</div>

Kairos is an early-stage background job runner for Gleam on the BEAM. On `main` today it provides typed worker contracts, PostgreSQL-backed job persistence, queue configuration, public enqueue APIs, and atomic job claiming.

Automatic worker execution, retry backoff, and recovery behavior are still being built, so expect the `0.x` API and supervision model to keep moving.

## Installation

Kairos is not published to Hex yet.

Once the package is published, installation will be:

```sh
gleam add kairos
```

## Current Scope

Kairos on `main` currently supports:

- defining typed workers with explicit payload encoding and decoding
- configuring named queues and supervising Kairos inside a host app
- enqueueing jobs with queue, priority, max-attempts, and schedule options
- storing jobs in PostgreSQL and atomically claiming runnable jobs per queue

Kairos on `main` does not yet run an always-on execution loop. Claiming is available now, but execution remains app-owned until the runtime layer lands.

## Setup

Kairos runs inside the consuming application, so the host app should own environment loading and pool supervision.

Kairos exposes migrations through `kairos/migration`.
Apply `migration.migrations()` with your existing migration runner, start your PostgreSQL pool, build a `config.Config`, and start Kairos in your supervision tree.

```gleam
import gleam/erlang/process
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import kairos
import kairos/config
import kairos/migration
import kairos/queue
import kairos/supervision
import pog

pub fn database_pool(
  pool_name: process.Name(pog.Message),
  database_url: String,
) -> Result(ChildSpecification(pog.Connection), Nil) {
  use config <- result.try(pog.url_config(pool_name, database_url))
  Ok(pog.supervised(config))
}

pub fn kairos_child(
  pool_name: process.Name(pog.Message),
) -> Result(ChildSpecification(supervision.Runtime), config.ConfigError) {
  let connection = pog.named_connection(pool_name)
  use default_queue <- result.try(
    queue.new(name: "default", concurrency: 10, poll_interval_ms: 1_000),
  )
  use kairos_config <- result.try(
    config.new(connection: connection, queues: [default_queue]),
  )
  Ok(kairos.supervised(kairos_config))
}
```

## Enqueueing Jobs

`main` already exposes a public enqueue API. A worker defines typed arguments plus explicit encoding, decoding, and perform behavior:

```gleam
import kairos
import kairos/config
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

pub fn enqueue_report(
  kairos_config: config.Config,
) -> Nil {
  let assert Ok(_) =
    kairos.enqueue(
      kairos_config,
      report_worker(),
      ReportArgs(account_id: "acct_123"),
    )

  Nil
}
```

## Claiming Jobs

Kairos can already claim runnable jobs atomically from PostgreSQL. That is the current execution boundary on `main`:

```gleam
import gleam/time/timestamp
import kairos/config
import kairos/postgres/job_store

pub fn claim_default_queue(
  kairos_config: config.Config,
) -> List(job_store.PersistedJob) {
  let assert Ok(claimed_jobs) =
    job_store.claim_available(
      config.connection(kairos_config),
      "default",
      timestamp.system_time(),
      10,
    )

  claimed_jobs
}
```

## PostgreSQL Setup

The PostgreSQL integration suite expects:

- a reachable PostgreSQL database
- the `pgcrypto` extension to be available
- a dedicated test database

By default the integration tests use:

```sh
postgresql://postgres:postgres@localhost:5432/kairos_test?sslmode=disable
```

Override that by setting `KAIROS_TEST_DATABASE_URL` when your local PostgreSQL setup differs.

The integration harness recreates `kairos_jobs`, so do not point `KAIROS_TEST_DATABASE_URL` at a shared development or production database.
If your deployment role cannot create extensions, install `pgcrypto` before running the Kairos schema migration.

One local setup is:

```sh
createdb kairos_test
export KAIROS_TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/kairos_test?sslmode=disable
```

## Development Setup

```sh
gleam deps download
createdb kairos_test
```

## Development

```sh
gleam format
gleam test
```

See `CONTRIBUTING.md` for the CI support policy, required merge checks, and CodeRabbit review defaults.
