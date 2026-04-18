import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import kairos/backoff
import kairos/config
import kairos/postgres/job_store
import kairos/worker
import pog

pub type RunnerArg {
  RunnerArg(
    config: config.Config,
    job: job_store.PersistedJob,
    now: timestamp.Timestamp,
  )
}

type LifecycleTransition {
  MarkCompleted
  MarkRetryable(String)
  MarkDiscarded(String)
  MarkCancelled(String)
}

@internal
pub fn start(argument: RunnerArg) -> actor.StartResult(String) {
  let RunnerArg(job:, ..) = argument
  let job_store.PersistedJob(id:, ..) = job
  let pid =
    process.spawn(fn() {
      case run(argument) {
        Ok(_) -> Nil
        Error(error) ->
          io.println(
            "kairos runner persistence failed: " <> string.inspect(error),
          )
      }
      Nil
    })
  Ok(actor.Started(pid:, data: id))
}

@internal
pub fn run_claimed(
  config: config.Config,
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  run(RunnerArg(config:, job: claimed_job, now: now))
}

fn run(
  argument: RunnerArg,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  let RunnerArg(config:, job: claimed_job, now:) = argument
  let transition = determine_transition(config, claimed_job)
  persist_or_recover_transition(
    config,
    config.connection(config),
    claimed_job,
    now,
    transition,
  )
}

fn determine_transition(
  config: config.Config,
  claimed_job: job_store.PersistedJob,
) -> LifecycleTransition {
  let job_store.PersistedJob(
    worker_name: worker_name,
    payload: payload,
    attempt: attempt,
    max_attempts: max_attempts,
    ..,
  ) = claimed_job

  case config.find_worker(config, worker_name) {
    Some(registered_worker) ->
      case worker.execute_payload(registered_worker, payload) {
        worker.Succeeded -> MarkCompleted
        worker.RetryRequested(reason) ->
          retry_or_discard(attempt, max_attempts, "retry", reason)
        worker.DiscardRequested(reason) ->
          MarkDiscarded(format_failure("discard", attempt, reason))
        worker.CancelRequested(reason) ->
          MarkCancelled(format_failure("cancel", attempt, reason))
        worker.DecodeFailed(reason) ->
          MarkDiscarded(format_failure("decode", attempt, reason))
        worker.Crashed(reason) ->
          retry_or_discard(attempt, max_attempts, "crash", reason)
      }
    None ->
      MarkDiscarded(format_failure(
        "missing_worker",
        attempt,
        "worker not configured",
      ))
  }
}

fn retry_or_discard(
  attempt: Int,
  max_attempts: Int,
  kind: String,
  reason: String,
) -> LifecycleTransition {
  let formatted = format_failure(kind, attempt, reason)
  case attempt < max_attempts {
    True -> MarkRetryable(formatted)
    False -> MarkDiscarded(formatted)
  }
}

fn persist_transition(
  config: config.Config,
  connection: pog.Connection,
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
  transition: LifecycleTransition,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  let job_store.PersistedJob(id:, ..) = claimed_job

  case transition {
    MarkCompleted -> job_store.complete(connection, id, now)
    MarkRetryable(error) ->
      job_store.retry(
        connection,
        id,
        retry_scheduled_at(config, claimed_job, now, error),
        error,
      )
    MarkDiscarded(error) -> job_store.discard(connection, id, now, error)
    MarkCancelled(error) -> job_store.cancel(connection, id, now, error)
  }
}

fn persist_or_recover_transition(
  config: config.Config,
  connection: pog.Connection,
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
  transition: LifecycleTransition,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  case persist_transition(config, connection, claimed_job, now, transition) {
    Ok(persisted_job) -> Ok(persisted_job)
    Error(error) ->
      recover_transition_failure(
        config,
        connection,
        claimed_job,
        now,
        transition,
        error,
      )
  }
}

fn recover_transition_failure(
  config: config.Config,
  connection: pog.Connection,
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
  transition: LifecycleTransition,
  error: job_store.StoreError,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  let job_store.PersistedJob(id:, attempt:, max_attempts:, ..) = claimed_job
  let recovery_error =
    format_failure("persistence", attempt, string.inspect(error))

  case transition {
    MarkRetryable(_) ->
      case attempt < max_attempts {
        True ->
          job_store.retry(
            connection,
            id,
            retry_scheduled_at(config, claimed_job, now, recovery_error),
            recovery_error,
          )
        False -> Error(error)
      }
    _ -> Error(error)
  }
}

@internal
pub fn retry_scheduled_at(
  config: config.Config,
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
  error: String,
) -> timestamp.Timestamp {
  timestamp.add(
    now,
    duration.seconds(retry_backoff_seconds(config, claimed_job, error)),
  )
}

fn format_failure(kind: String, attempt: Int, reason: String) -> String {
  "kind="
  <> kind
  <> " attempt="
  <> int.to_string(attempt)
  <> " reason="
  <> string.replace(reason, "\n", " ")
}

fn retry_backoff_seconds(
  config: config.Config,
  claimed_job: job_store.PersistedJob,
  error: String,
) -> Int {
  let job_store.PersistedJob(worker_name: worker_name, ..) = claimed_job
  let context = retry_context(claimed_job, error)

  case config.find_worker(config, worker_name) {
    Some(registered_worker) ->
      worker.backoff_seconds(registered_worker, context)
    None -> backoff.seconds(backoff.default_policy(), context)
  }
}

fn retry_context(
  claimed_job: job_store.PersistedJob,
  error: String,
) -> backoff.Context {
  let job_store.PersistedJob(
    attempt: attempt,
    max_attempts: max_attempts,
    worker_name: worker_name,
    queue_name: queue_name,
    ..,
  ) = claimed_job

  backoff.new_context(
    attempt: attempt,
    max_attempts: max_attempts,
    worker_name: worker_name,
    queue_name: queue_name,
    error: error,
  )
}
