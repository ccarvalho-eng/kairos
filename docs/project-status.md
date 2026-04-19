# Project Status

Kairos is archived and should be treated as an experimental weekend project.

The repository remains useful as a reference for queue/runtime boundaries, but it is not an active effort and no release track is planned.

## What The Experiment Already Does

- defines workers with explicit encode and decode boundaries
- persists jobs in PostgreSQL
- supports per-queue polling and supervised execution
- retries failed jobs with configurable backoff
- cancels jobs before execution
- recovers stale `executing` jobs

## Why Work Stopped

Kairos surfaced a real correctness problem around execution ownership and stale recovery for long-running jobs.

At that point the project stopped making sense to continue in its current form:

- the current `attempted_at + stale_for` recovery model is not strong enough
- the next fixes move into subtle distributed ownership design
- existing libraries already cover some of those designs more credibly
- there is not yet a clear differentiator that justifies carrying Kairos forward

## Stability Expectations

- do not expect further feature work
- do not treat the current runtime as production-ready
- expect the repository to remain as historical reference rather than an evolving package

## Good Fit Today

Kairos is a good fit today if you want:

- a compact example of a PostgreSQL-backed queue runtime in Gleam
- a codebase to study queue polling, claiming, retries, and supervision boundaries
- a concrete example of where execution-ownership problems begin

## Not The Goal

Kairos is not trying to become a maintained production queue.

If active development resumes in the future it should start with a fresh design decision around execution ownership and stale recovery, not incremental feature work on top of the current runtime.
