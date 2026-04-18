# Kairos

Kairos is a background job runner for Gleam on the BEAM with typed worker contracts, PostgreSQL-backed persistence, and explicit queue configuration.

Kairos is in early `0.x` development. The package API and supervision behavior are still being established.

## Installation

Kairos is not published to Hex yet.

Once the package is published, installation will be:

```sh
gleam add kairos
```

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
