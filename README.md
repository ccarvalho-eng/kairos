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

One local setup is:

```sh
createdb kairos_test
export KAIROS_TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/kairos_test?sslmode=disable
```

## Existing Apps

Kairos is a library, so the consuming application should own environment loading and pool supervision.
For existing Gleam/OTP apps, the recommended shape is to read `DATABASE_URL` in the application layer, build a `pog.Config`, and start the pool in your supervision tree.

```gleam
import envoy
import gleam/erlang/process.{type Name}
import gleam/result
import pog

pub fn read_database_config(
  pool_name: Name(pog.Message),
) -> Result(pog.Config, Nil) {
  use database_url <- result.try(envoy.get("DATABASE_URL"))
  pog.url_config(pool_name, database_url)
}
```

Then apply `schema.migrations()` with your existing migration runner and pass the resulting `pog.Connection` into the Kairos persistence modules.

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
