# Kairos: BEAM-Native Durable Jobs for Gleam

## Summary

Kairos will be a greenfield Gleam library for durable background job processing on the BEAM, inspired by Oban's reliability model but shaped around Gleam's typed, explicit mental model.

The first serious release will target:
- `gleam 1.x` on the Erlang target only
- PostgreSQL only
- single-node correctness and recovery
- typed worker modules instead of untyped map payloads
- durable enqueueing, delayed jobs, retries, uniqueness, supervision, telemetry, and admin APIs
- no dashboard and no recurring cron engine in v1

The product thesis is: Oban's durability and operational trust, but with Gleam-native APIs that make job contracts explicit and type-guided.

## Key Changes / Architecture

### 1. Public model and package shape
Kairos should be delivered as a reusable Gleam package named `kairos`.
Primary public modules:
- `kairos` for startup, configuration, enqueue APIs, and admin entrypoints
- `kairos/job` for job data types, metadata, state, and enqueue request builders
- `kairos/worker` for the typed worker contract
- `kairos/queue` for queue definitions and execution policy
- `kairos/backoff` for retry policy behavior
- `kairos/telemetry` for event types and subscription hooks
- `kairos/testing` for test helpers and worker execution assertions

Internal-only modules should own polling, claiming, dispatch, encoding, and DB access so the public surface stays small and explicit.

### 2. Gleam-native worker model
Jobs should be defined as typed worker modules rather than stringly-typed handler registration.
Each worker contract should include:
- a stable job name
- an argument type
- encode/decode functions between the typed args and stored payload
- a `perform` callback returning a structured result
- optional retry/backoff/queue/priority/uniqueness defaults

This is the main departure from Oban's Elixir ergonomics. In Kairos, the durable boundary is explicit: typed args in user code, serialized payload at storage boundaries.

### 3. Runtime architecture
Kairos should run under `gleam_otp` supervision and use a small set of actors:
- a supervisor root
- one poller/dispatcher actor per queue
- one execution supervisor for spawned job runners
- one reaper/recovery actor for stale claimed jobs
- one notifier/telemetry broadcaster actor

Execution flow:
1. enqueue persists a job row in Postgres
2. queue actor polls for available jobs
3. queue actor claims jobs atomically in SQL
4. queue actor starts runner processes for claimed jobs
5. runner executes typed worker code and returns a structured outcome
6. queue actor persists final state transition and emits telemetry

Single-node correctness is the only guarantee in v1, but SQL claiming logic should be written so later multi-node support is an additive step rather than a rewrite.

### 4. Storage and job lifecycle
Use PostgreSQL as the only concrete adapter in v1.
Core table design should support:
- pending
- scheduled
- executing
- retryable
- completed
- discarded
- cancelled

Each stored job should include:
- id
- worker name
- encoded args payload
- queue
- state
- attempt and max attempts
- priority
- scheduled_at
- attempted_at
- completed_at / discarded_at / cancelled_at
- uniqueness fields
- error history
- inserted_at / updated_at

Required v1 behaviors:
- transactional enqueue API
- delayed execution via `scheduled_at`
- retry with pluggable backoff policy
- uniqueness over selected fields and time window
- cancellation before execution
- stale execution recovery after crash/restart
- admin queries for listing and mutating jobs by id/state/queue/worker

Recurring cron-style jobs are explicitly deferred until after the core lifecycle is stable.

### 5. API and ergonomics
Expose two primary enqueue styles:
- `enqueue(worker, args)`
- `enqueue_with(worker, args, options)`

Options should cover:
- queue
- scheduled time / delay
- max attempts
- priority
- uniqueness policy
- tags or metadata if needed for filtering

Worker execution should return a structured result such as:
- success
- retry with reason
- discard with reason
- cancel with reason

Do not expose raw SQL or DB rows in the public API. Public admin APIs should return typed domain records, not transport-shaped maps.

## Delivery Plan

### Phase 1. Foundation
- Create the `kairos` package, supervision tree, config model, and Postgres persistence layer
- Define the worker contract, job record, state machine, and enqueue API
- Ship migrations and reference schema

### Phase 2. Reliable execution core
- Implement queue polling, atomic claiming, runner supervision, and state transitions
- Add delayed jobs, retries, configurable backoff, cancellation, and recovery of stale executions
- Add structured error capture and event emission at lifecycle boundaries

### Phase 3. Operability and developer UX
- Add admin/query APIs, filtering by queue/worker/state, and safe mutation operations
- Add telemetry/events hooks and logger integration
- Add `kairos/testing` helpers for worker tests and integration tests

### Phase 4. Hardening for 1.0 direction
- Document extension seams for future multi-node support
- Document future adapter boundary, but do not generalize it prematurely in v1
- Leave recurring jobs, dashboard, and broader cluster semantics as post-v1 roadmap items

## Test Plan

Required tests:
- enqueue persists the correct worker name, payload, queue, and schedule data
- queue actor claims only available jobs and respects priority/order policy
- a successful worker transitions jobs to `completed`
- retryable failures increment attempts and reschedule correctly
- discard paths move jobs to terminal failed state with captured error history
- delayed jobs do not run before `scheduled_at`
- uniqueness prevents conflicting enqueues within the configured scope/window
- cancellation prevents pending scheduled jobs from running
- queue actor crash or node-local process death does not permanently orphan claimed jobs
- stale execution recovery returns abandoned jobs to a runnable state
- typed encode/decode failures are surfaced as structured boundary errors
- admin APIs return consistent typed representations of persisted jobs

Test mix:
- unit tests for worker contract, backoff logic, uniqueness calculation, and state transitions
- integration tests against PostgreSQL for claiming, recovery, and enqueue/perform lifecycle
- supervisor tests for crash recovery and queue restart behavior

## Assumptions and Defaults

- Project name is `Kairos`
- BEAM-only is intentional, not temporary compatibility debt
- PostgreSQL is the only shipped backend in v1
- Single-node production support is the only operational promise in v1
- Delayed one-off jobs are in v1; recurring cron jobs are out of scope
- No dashboard in v1; operability is via typed APIs, logs, and telemetry/events
- The design should stay adapter-aware internally, but no public pluggable backend API should be committed until the Postgres implementation is proven
- The main differentiator from Oban is typed job contracts and Gleam-first ergonomics, not feature parity on day one
