# Stale Recovery

Use stale recovery when a job has been left in `executing` after interruption, crash, or restart.

Kairos recovers these jobs in bounded batches through `kairos.recover_stale(...)`.

## Recover A Queue

```gleam
import gleam/time/duration
import gleam/time/timestamp
import kairos

pub fn recover_default_queue(
  runtime: supervision.Runtime,
) -> Result(Int, kairos.RecoveryError) {
  kairos.recover_stale(
    runtime,
    "default",
    timestamp.system_time(),
    duration.minutes(5),
  )
}
```

The returned `Int` is the number of jobs recovered across all processed batches.

## How Kairos Decides A Job Is Stale

Kairos looks for jobs that are:

- in `executing`
- old enough according to the `stale_for` window
- still owned by the target queue

## Recovery Outcomes

Recovered jobs move into one of two paths:

- back to a runnable retryable path
- into a terminal state when no more retries are legal

Use this as an operational recovery tool after unexpected interruption, not as a normal control path.
