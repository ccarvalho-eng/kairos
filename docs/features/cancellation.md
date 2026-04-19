# Cancellation

Kairos can cancel jobs before they start executing.

Use this when a job is:

- still `pending`
- `scheduled`
- `retryable`

Cancellation does not stop work that is already executing.

## Cancel A Job

```gleam
import kairos

pub fn cancel_report(
  kairos_config: config.Config,
  job_id: String,
) -> Result(Nil, kairos.CancelError) {
  kairos.cancel(kairos_config, job_id)
}
```

## What Cancellation Does

When cancellation succeeds, Kairos:

- updates the job state to `cancelled`
- records `cancelled_at`
- appends a cancellation reason to the job errors

## What Cancellation Does Not Do

Cancellation does not:

- kill an already-running worker process
- remove the job row from PostgreSQL
- bypass queue validation or worker registration rules
