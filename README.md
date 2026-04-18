<div align="center">

<img width="60" alt="kairos-logo" src="https://github.com/user-attachments/assets/95e17f1e-5564-4304-836e-9d21eab5c1ce" />

# Kairos

[![CI](https://github.com/ccarvalho-eng/kairos/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ccarvalho-eng/kairos/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](./LICENSE)

Typed background jobs for Gleam on the BEAM.

</div>

Kairos is an early-stage background job runner for Gleam on the BEAM. On `main` today it provides typed worker contracts, PostgreSQL-backed job persistence, queue configuration, autonomous queue polling, supervised job execution, cancellation before execution, retry backoff, and stale execution recovery.

Expect the `0.x` API and supervision model to keep moving while the runtime and operational surface harden.

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
- polling queues automatically and dispatching claimed jobs through supervised runners
- cancelling queued jobs before execution
- retrying failed jobs with configurable backoff
- recovering stale `executing` jobs back into a runnable or terminal state

Kairos on `main` does not yet provide a full operational surface for inspection, telemetry, pruning, or advanced queue controls. The runtime is useful now, but still intentionally narrow.

## Docs

Start here:

- [`docs/README.md`](./docs/README.md)
- [`docs/setup.md`](./docs/setup.md)
- [`docs/architecture.md`](./docs/architecture.md)

## Quick Start

Kairos runs inside the consuming application. The host app owns:

- PostgreSQL pool setup
- migration execution
- queue definitions
- worker definitions and registration
- supervision startup

The full setup path, worker examples, and per-job option overrides live in [`docs/setup.md`](./docs/setup.md).

## Runtime Summary

On `main`, Kairos can:

- enqueue typed jobs
- poll queues automatically
- claim runnable jobs atomically
- execute jobs in supervised runners
- retry failures with configurable backoff
- cancel jobs before execution
- recover stale `executing` jobs

The runtime topology and module boundaries are documented in [`docs/architecture.md`](./docs/architecture.md).

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

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the CI support policy, required merge checks, and CodeRabbit review defaults.
