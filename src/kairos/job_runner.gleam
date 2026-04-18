import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
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
        retry_scheduled_at(claimed_job, now),
        error,
      )
    MarkDiscarded(error) -> job_store.discard(connection, id, now, error)
    MarkCancelled(error) -> job_store.cancel(connection, id, now, error)
  }
}

fn persist_or_recover_transition(
  connection: pog.Connection,
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
  transition: LifecycleTransition,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  case persist_transition(connection, claimed_job, now, transition) {
    Ok(persisted_job) -> Ok(persisted_job)
    Error(error) ->
      recover_transition_failure(connection, claimed_job, now, error)
  }
}

fn recover_transition_failure(
  connection: pog.Connection,
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
  error: job_store.StoreError,
) -> Result(job_store.PersistedJob, job_store.StoreError) {
  let job_store.PersistedJob(id:, attempt:, ..) = claimed_job
  let recovery_error =
    format_failure("persistence", attempt, string.inspect(error))

  job_store.retry(
    connection,
    id,
    retry_scheduled_at(claimed_job, now),
    recovery_error,
  )
}

@internal
pub fn retry_scheduled_at(
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
) -> timestamp.Timestamp {
  let job_store.PersistedJob(attempt:, max_attempts:, ..) = claimed_job
  timestamp.add(
    now,
    duration.seconds(default_backoff_seconds(attempt, max_attempts)),
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

fn default_backoff_seconds(attempt: Int, max_attempts: Int) -> Int {
  let clamped_attempt = case max_attempts <= 20 {
    True -> attempt
    False ->
      float.round(int.to_float(attempt) /. int.to_float(max_attempts) *. 20.0)
  }

  15 + pow2(int.min(clamped_attempt, 20))
}

fn pow2(exponent: Int) -> Int {
  case exponent <= 0 {
    True -> 1
    False -> 2 * pow2(exponent - 1)
  }
}
