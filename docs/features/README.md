# Features

Use these pages after [`docs/setup.md`](../setup.md).

Read them in this order:

1. [Enqueueing](./enqueueing.md)
   Learn worker defaults, per-job overrides, and `enqueue` vs `enqueue_with`.
2. [Scheduling](./scheduling.md)
   Learn how to delay execution and route scheduled jobs to the right queue.
3. [Retries And Backoff](./retries.md)
   Learn how retries are configured and how to attach a backoff policy to a worker.
4. [Cancellation](./cancellation.md)
   Learn how to cancel jobs before they start executing.
5. [Stale Recovery](./recovery.md)
   Learn how to recover old `executing` jobs after interruption or restart.
