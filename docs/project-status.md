# Project Status

Kairos is a `0.x` background job runner for Gleam.

## What Kairos Already Does

- defines workers with explicit encode and decode boundaries
- persists jobs in PostgreSQL
- supports per-queue polling and supervised execution
- retries failed jobs with configurable backoff
- cancels jobs before execution
- recovers stale `executing` jobs

## What Is Still Intentionally Narrow

Kairos is already usable, but it is not yet a full operational platform.

Current gaps include:

- broader admin and query APIs
- telemetry and structured runtime events
- automatic job pruning and retention policies
- advanced queue controls such as pause, drain, or scaling behavior
- broader multi-node and operational guarantees

## Stability Expectations

- expect the `0.x` API and supervision model to evolve
- expect module boundaries to keep tightening as the runtime grows
- expect backwards-incompatible changes when they simplify the public surface or improve correctness

## Good Fit Today

Kairos is a good fit today if you want:

- background jobs in a Gleam application
- PostgreSQL-backed persistence
- a runtime you can understand end to end
- a narrower feature set with room to evolve

## Not The Goal Right Now

Kairos is not trying to ship every queueing feature at once.

The current priority is:

1. keep the execution model clear
2. keep the public API small
3. harden the operational surface in focused slices
