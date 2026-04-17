# Kairos

Kairos is a durable background job library for Gleam on the BEAM, designed around typed job contracts, explicit serialization boundaries, and operational clarity.

Kairos is in early `0.x` development. The package API and runtime behavior are still being established.

## Installation

Kairos is not published to Hex yet.

Once the package is published, installation will be:

```sh
gleam add kairos
```

## PostgreSQL Schema

Kairos ships PostgreSQL schema definitions through `kairos/postgres/schema`.
Applications are expected to apply `schema.migrations()` in version order with their own migration runner.

## PostgreSQL Setup

The PostgreSQL integration suite expects:

- a reachable PostgreSQL database
- the `pgcrypto` extension to be available
- a dedicated test database, referenced by `KAIROS_TEST_DATABASE_URL`

The integration harness recreates `kairos_jobs`, so do not point `KAIROS_TEST_DATABASE_URL` at a shared development or production database.
If your deployment role cannot create extensions, install `pgcrypto` before running the Kairos schema migration.

One local setup is:

```sh
createdb kairos_test
export KAIROS_TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/kairos_test?sslmode=disable
```

## Existing Apps

Kairos is a library, so the consuming application should own environment loading and pool supervision.
For existing Gleam/OTP apps, the recommended shape is:

- read `DATABASE_URL` in the application layer using your existing config or env-loading approach
- include an explicit `sslmode` in that URL outside local development
- build a `pog.Config`
- start the `pog` pool in your supervision tree
- pass a named `pog.Connection` into Kairos configuration and persistence modules

```gleam
import gleam/erlang/process
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import kairos
import kairos/config
import kairos/runtime
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
) -> Result(ChildSpecification(runtime.Runtime), config.ConfigError) {
  let connection = pog.named_connection(pool_name)
  use default_queue <- result.try(
    config.queue(name: "default", concurrency: 10, poll_interval_ms: 1_000),
  )
  use kairos_config <- result.try(
    config.new(connection: connection, queues: [default_queue]),
  )
  Ok(kairos.supervised(kairos_config))
}
```

`pog.url_config/2` defaults to `sslmode=disable` when the URL omits an SSL mode, so production and other non-local environments should provide `sslmode=require`, `sslmode=verify-ca`, or `sslmode=verify-full` in `DATABASE_URL`.

`pog.supervised/1` connects asynchronously and retries in the background, so database reachability should be treated as a readiness concern in the host application rather than assuming the supervision tree only starts once PostgreSQL is available.

Then apply `schema.migrations()` with your existing migration runner and pass the resulting named `pog.Connection` into the Kairos persistence modules.

## Runtime Configuration

Kairos uses a typed runtime configuration and a queue-oriented supervision layout.
Queue definitions are explicit values from `kairos/config`, not ad hoc maps, and the host application decides when Kairos is started.

```gleam
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import kairos
import kairos/config
import kairos/runtime
import pog

pub fn build_kairos_config(
  connection: pog.Connection,
) -> Result(config.Config, config.ConfigError) {
  use default_queue <- result.try(
    config.queue(name: "default", concurrency: 10, poll_interval_ms: 1_000),
  )
  use mailers_queue <- result.try(
    config.queue(name: "mailers", concurrency: 3, poll_interval_ms: 2_000),
  )

  config.new(connection: connection, queues: [default_queue, mailers_queue])
}

pub fn kairos_child(
  connection: pog.Connection,
) -> Result(ChildSpecification(runtime.Runtime), config.ConfigError) {
  use kairos_config <- result.try(build_kairos_config(connection))
  Ok(kairos.supervised(kairos_config))
}
```

`kairos.start(config)` starts Kairos directly. `kairos.supervised(config)` returns a child specification so the host app can place Kairos inside its own supervision tree.

The runtime currently establishes the root supervisor and one queue supervisor per configured queue.
Each queue supervisor starts stub worker and poller processes so later queue execution work can replace those internals without changing the host application's startup shape.

## Development Setup

```sh
gleam deps download
createdb kairos_test
export KAIROS_TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/kairos_test?sslmode=disable
```

## Development

```sh
gleam format
gleam test
```
