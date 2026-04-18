import gleam/erlang/process
import gleam/int
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import kairos/config
import kairos/postgres/job_store
import pog

const recovery_batch_size = 100

const recovery_timeout_ms = 15_000

pub type Message {
  Recover(
    now: timestamp.Timestamp,
    stale_for: duration.Duration,
    reply_with: process.Subject(Result(Int, job_store.StoreError)),
  )
}

type State {
  State(config: config.Config, queue_name: String)
}

@internal
pub fn start(
  name name: process.Name(Message),
  config config: config.Config,
  queue_name queue_name: String,
) -> Result(actor.Started(Nil), actor.StartError) {
  actor.new(State(config: config, queue_name: queue_name))
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { actor.Started(pid: started.pid, data: Nil) })
}

@internal
pub fn supervised(
  name name: process.Name(Message),
  config config: config.Config,
  queue_name queue_name: String,
) -> ChildSpecification(Nil) {
  supervision.worker(fn() {
    start(name: name, config: config, queue_name: queue_name)
  })
}

@internal
pub fn recover(
  name: process.Name(Message),
  now: timestamp.Timestamp,
  stale_for: duration.Duration,
) -> Result(Int, job_store.StoreError) {
  actor.call(
    process.named_subject(name),
    waiting: recovery_timeout_ms,
    sending: fn(reply_with) {
      Recover(now: now, stale_for: stale_for, reply_with: reply_with)
    },
  )
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Recover(now:, stale_for:, reply_with:) -> {
      process.send(reply_with, recover_stale_jobs(state, now, stale_for))
      actor.continue(state)
    }
  }
}

fn recover_stale_jobs(
  state: State,
  now: timestamp.Timestamp,
  stale_for: duration.Duration,
) -> Result(Int, job_store.StoreError) {
  let attempted_before =
    timestamp.add(
      now,
      duration.milliseconds(-duration.to_milliseconds(stale_for)),
    )

  recover_stale_jobs_in_batches(state, now, attempted_before, 0)
}

fn recover_stale_jobs_in_batches(
  state: State,
  now: timestamp.Timestamp,
  attempted_before: timestamp.Timestamp,
  recovered_count: Int,
) -> Result(Int, job_store.StoreError) {
  let State(config:, queue_name:) = state

  let recovered_in_batch =
    pog.transaction(config.connection(config), fn(connection) {
      let stale_jobs =
        job_store.fetch_stale_executing(
          connection,
          queue_name,
          attempted_before,
          recovery_batch_size,
        )
      use stale_jobs <- result.try(stale_jobs)
      recover_jobs(connection, stale_jobs, now, 0)
    })
    |> map_transaction_error
  use recovered_in_batch <- result.try(recovered_in_batch)

  case recovered_in_batch {
    0 -> Ok(recovered_count)
    _ ->
      recover_stale_jobs_in_batches(
        state,
        now,
        attempted_before,
        recovered_count + recovered_in_batch,
      )
  }
}

fn recover_jobs(
  connection: pog.Connection,
  stale_jobs: List(job_store.PersistedJob),
  now: timestamp.Timestamp,
  recovered_count: Int,
) -> Result(Int, job_store.StoreError) {
  case stale_jobs {
    [] -> Ok(recovered_count)
    [stale_job, ..rest] -> {
      use _ <- result.try(recover_job(connection, stale_job, now))
      recover_jobs(connection, rest, now, recovered_count + 1)
    }
  }
}

fn recover_job(
  connection: pog.Connection,
  stale_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  let job_store.PersistedJob(id:, attempt:, max_attempts:, ..) = stale_job
  let error = stale_error(attempt)

  case attempt < max_attempts {
    True -> job_store.retry(connection, id, now, error)
    False -> job_store.discard(connection, id, now, error)
  }
}

fn stale_error(attempt: Int) -> String {
  "kind=stale attempt="
  <> int.to_string(attempt)
  <> " reason=stale execution recovered"
}

fn map_transaction_error(
  result: Result(Int, pog.TransactionError(job_store.StoreError)),
) -> Result(Int, job_store.StoreError) {
  case result {
    Ok(recovered_count) -> Ok(recovered_count)
    Error(pog.TransactionQueryError(error)) ->
      Error(job_store.QueryFailed(error))
    Error(pog.TransactionRolledBack(error)) -> Error(error)
  }
}
