import gleam/option.{Some}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import kairos
import kairos/config
import kairos/job
import kairos/postgres/job_store
import kairos/postgres/test_db
import kairos/queue
import kairos/worker
import pog

type MailArgs {
  MailArgs(recipient: String, template: String)
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn enqueue_uses_worker_defaults_and_persists_typed_payload_test() {
  test_db.with_database(fn(connection) {
    let kairos_config = build_config(connection)
    let contract = mail_worker()
    let args = MailArgs(recipient: "ops@example.com", template: "welcome")

    let assert Ok(enqueued) = kairos.enqueue(kairos_config, contract, args)
    let job.EnqueuedJob(
      id: id,
      args: stored_args,
      worker_name: worker_name,
      state: state,
      queue_name: queue_name,
      priority: priority,
      attempt: attempt,
      max_attempts: max_attempts,
      scheduled_at: scheduled_at,
      ..,
    ) = enqueued

    assert stored_args == args
    assert worker_name == "mailers.email"
    assert state == job.Pending
    assert queue_name == "mailers"
    assert priority == 3
    assert attempt == 0
    assert max_attempts == 5

    let assert Ok(Some(stored)) = job_store.fetch(connection, id)
    let job_store.PersistedJob(
      payload: payload,
      state: stored_state,
      queue_name: stored_queue,
      priority: stored_priority,
      max_attempts: stored_max_attempts,
      scheduled_at: stored_at,
      ..,
    ) = stored

    assert payload == worker.encode(contract, args)
    assert stored_state == job.Pending
    assert stored_queue == "mailers"
    assert stored_priority == 3
    assert stored_max_attempts == 5
    assert scheduled_at == stored_at
  })
}

pub fn enqueue_with_supports_delayed_execution_test() {
  test_db.with_database(fn(connection) {
    let kairos_config = build_config(connection)
    let contract = mail_worker()
    let args = MailArgs(recipient: "slow@example.com", template: "digest")
    let now = timestamp.system_time()
    let later = timestamp.add(now, duration.minutes(10))
    let assert Ok(queued) =
      job.with_queue(worker.default_options(contract), "default")
    let assert Ok(retrying) = job.with_max_attempts(queued, 2)
    let prioritized = job.with_priority(retrying, 8)
    let options = job.with_schedule(prioritized, job.At(later))

    let assert Ok(enqueued) =
      kairos.enqueue_with(kairos_config, contract, args, options)
    let job.EnqueuedJob(
      id: id,
      args: stored_args,
      state: state,
      queue_name: queue_name,
      priority: priority,
      max_attempts: max_attempts,
      scheduled_at: scheduled_at,
      ..,
    ) = enqueued

    assert stored_args == args
    assert state == job.Scheduled
    assert queue_name == "default"
    assert priority == 8
    assert max_attempts == 2
    assert scheduled_at == test_db.to_postgres_precision(later)

    let assert Ok(Some(stored)) = job_store.fetch(connection, id)
    let job_store.PersistedJob(state: stored_state, scheduled_at: stored_at, ..) =
      stored

    assert stored_state == job.Scheduled
    assert stored_at == test_db.to_postgres_precision(later)
  })
}

pub fn enqueue_with_rejects_unknown_queues_test() {
  test_db.with_database(fn(connection) {
    let kairos_config = build_config(connection)
    let contract = mail_worker()
    let args = MailArgs(recipient: "ops@example.com", template: "welcome")
    let assert Ok(options) =
      job.with_queue(worker.default_options(contract), "unknown")

    assert kairos.enqueue_with(kairos_config, contract, args, options)
      == Error(kairos.QueueNotConfigured("unknown"))

    let assert Ok(stored_jobs) =
      job_store.fetch_available(connection, timestamp.system_time(), 10)
    assert stored_jobs == []
  })
}

fn build_config(connection: pog.Connection) -> config.Config {
  let assert Ok(default_queue) =
    queue.new(name: "default", concurrency: 10, poll_interval_ms: 1000)
  let assert Ok(mailers_queue) =
    queue.new(name: "mailers", concurrency: 5, poll_interval_ms: 2000)
  let assert Ok(kairos_config) =
    config.new(
      connection: connection,
      queues: [default_queue, mailers_queue],
      workers: [],
    )
  kairos_config
}

fn mail_worker() -> worker.Worker(MailArgs) {
  let assert Ok(queue_options) =
    job.with_queue(job.default_enqueue_options(), "mailers")
  let assert Ok(retry_options) = job.with_max_attempts(queue_options, 5)
  let options = job.with_priority(retry_options, 3)

  worker.new(
    "mailers.email",
    encode_mail_args,
    fn(_payload) { Error(worker.DecodeError("not used in enqueue tests")) },
    fn(_args) { worker.Success },
    options,
  )
}

fn encode_mail_args(args: MailArgs) -> String {
  let MailArgs(recipient:, template:) = args
  recipient <> "|" <> template
}
