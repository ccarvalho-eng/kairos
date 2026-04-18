import gleam/time/timestamp
import kairos/postgres/job_store
import kairos/queue
import pog

@internal
pub fn poll(
  connection: pog.Connection,
  queue_definition: queue.Queue,
  now: timestamp.Timestamp,
) -> Result(List(job_store.PersistedJob), job_store.StoreError) {
  job_store.claim_available(
    connection,
    queue.name(queue_definition),
    now,
    queue.concurrency(queue_definition),
  )
}
