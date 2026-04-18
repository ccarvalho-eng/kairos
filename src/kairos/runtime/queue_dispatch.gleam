import exception
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/result
import gleam/string
import gleam/time/timestamp
import kairos/config
import kairos/postgres/job_store
import kairos/runtime/job_runner
import pog

pub type DispatchClaimedError {
  QueueRuntimeUnavailable(String, actor.StartError)
  RunnerStartFailed(actor.StartError)
  ReleaseClaimedFailed(actor.StartError, job_store.StoreError)
}

@internal
pub fn dispatch_claimed(
  config: config.Config,
  queue_name: String,
  runner_supervisor_name: process.Name(
    factory_supervisor.Message(job_runner.RunnerArg, String),
  ),
  claimed_jobs: List(job_store.PersistedJob),
  now: timestamp.Timestamp,
) -> Result(List(process.Pid), DispatchClaimedError) {
  let runner_supervisor = factory_supervisor.get_by_name(runner_supervisor_name)

  start_claimed_jobs(
    runner_supervisor,
    config,
    queue_name,
    claimed_jobs,
    now,
    [],
  )
}

fn start_claimed_jobs(
  runner_supervisor: factory_supervisor.Supervisor(job_runner.RunnerArg, String),
  config: config.Config,
  queue_name: String,
  claimed_jobs: List(job_store.PersistedJob),
  now: timestamp.Timestamp,
  started_pids: List(process.Pid),
) -> Result(List(process.Pid), DispatchClaimedError) {
  case claimed_jobs {
    [] -> Ok(list.reverse(started_pids))
    [claimed_job, ..rest] -> {
      case start_claimed_job(runner_supervisor, config, claimed_job, now) {
        Ok(started) ->
          start_claimed_jobs(runner_supervisor, config, queue_name, rest, now, [
            started.pid,
            ..started_pids
          ])

        Error(start_error) -> {
          let unstarted_jobs = [claimed_job, ..rest]

          case started_pids, supervisor_unavailable(start_error) {
            [], True ->
              case
                release_claimed_jobs(
                  config,
                  config.connection(config),
                  unstarted_jobs,
                  now,
                  start_error,
                )
              {
                Ok(Nil) ->
                  Error(QueueRuntimeUnavailable(queue_name, start_error))
                Error(cleanup_error) ->
                  Error(ReleaseClaimedFailed(start_error, cleanup_error))
              }
            _, _ ->
              // Keep already-started runners alive and only release the
              // unstarted tail back into the queue.
              case
                release_claimed_jobs(
                  config,
                  config.connection(config),
                  unstarted_jobs,
                  now,
                  start_error,
                )
              {
                Ok(Nil) -> Error(RunnerStartFailed(start_error))
                Error(cleanup_error) ->
                  Error(ReleaseClaimedFailed(start_error, cleanup_error))
              }
          }
        }
      }
    }
  }
}

fn start_claimed_job(
  runner_supervisor: factory_supervisor.Supervisor(job_runner.RunnerArg, String),
  config: config.Config,
  claimed_job: job_store.PersistedJob,
  now: timestamp.Timestamp,
) -> Result(actor.Started(String), actor.StartError) {
  case
    exception.rescue(fn() {
      factory_supervisor.start_child(
        runner_supervisor,
        job_runner.RunnerArg(config:, job: claimed_job, now: now),
      )
    })
  {
    Ok(start_result) -> start_result
    Error(exception.Exited(reason)) ->
      Error(actor.InitExited(process.Abnormal(reason)))
    Error(exception.Errored(reason)) ->
      Error(actor.InitFailed("errored: " <> string.inspect(reason)))
    Error(exception.Thrown(reason)) ->
      Error(actor.InitFailed("thrown: " <> string.inspect(reason)))
  }
}

fn release_claimed_jobs(
  config: config.Config,
  connection: pog.Connection,
  claimed_jobs: List(job_store.PersistedJob),
  now: timestamp.Timestamp,
  start_error: actor.StartError,
) -> Result(Nil, job_store.StoreError) {
  case claimed_jobs {
    [] -> Ok(Nil)
    [claimed_job, ..rest] -> {
      let job_store.PersistedJob(id:, attempt:, ..) = claimed_job
      let failure_reason = format_dispatch_failure(attempt, start_error)
      use _ <- result.try(job_store.retry(
        connection,
        id,
        job_runner.retry_scheduled_at(config, claimed_job, now, failure_reason),
        failure_reason,
      ))
      release_claimed_jobs(config, connection, rest, now, start_error)
    }
  }
}

fn format_dispatch_failure(
  attempt: Int,
  start_error: actor.StartError,
) -> String {
  "kind=runner_start attempt="
  <> int.to_string(attempt)
  <> " reason="
  <> string.replace(string.inspect(start_error), "\n", " ")
}

fn supervisor_unavailable(start_error: actor.StartError) -> Bool {
  case start_error {
    // This relies on the BEAM's noproc formatting. A false negative is safe
    // here because the fallback path still attempts to release claimed jobs.
    actor.InitExited(process.Abnormal(reason)) ->
      string.contains(string.lowercase(string.inspect(reason)), "noproc")
    _ -> False
  }
}
