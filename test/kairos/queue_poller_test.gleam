import gleam/erlang/process
import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import kairos
import kairos/config
import kairos/job
import kairos/postgres/job_store
import kairos/postgres/test_db
import kairos/queue
import kairos/supervision
import kairos/worker
import pog

type ExampleArgs {
  ExampleArgs(name: String)
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn poller_automatically_dispatches_pending_jobs_test() {
  test_db.with_database(fn(connection) {
    let contract = success_worker("workers.pending")
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 1, poll_interval_ms: 25)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)

    let assert Ok(enqueued) =
      kairos.enqueue(kairos_config, contract, ExampleArgs(name: "pending"))
    let job.EnqueuedJob(id:, ..) = enqueued

    let completed = wait_for_completed_job(connection, id, 80)
    let job_store.PersistedJob(state:, ..) = completed

    assert state == job.Completed

    stop_process(started.pid)
  })
}

pub fn poller_remains_alive_across_idle_cycles_test() {
  test_db.with_database(fn(connection) {
    let contract = success_worker("workers.idle")
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 1, poll_interval_ms: 25)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)
    let runtime = started.data

    let assert Ok(initial_poller_pid) =
      supervision.queue_poller_pid(runtime, "default")

    process.sleep(125)

    let assert Ok(current_poller_pid) =
      supervision.queue_poller_pid(runtime, "default")
    let assert Ok(enqueued) =
      kairos.enqueue(kairos_config, contract, ExampleArgs(name: "idle"))
    let job.EnqueuedJob(id:, ..) = enqueued
    let completed = wait_for_completed_job(connection, id, 80)
    let job_store.PersistedJob(state:, ..) = completed

    assert process.is_alive(current_poller_pid)
    assert current_poller_pid == initial_poller_pid
    assert state == job.Completed

    stop_process(started.pid)
  })
}

pub fn poller_dispatches_scheduled_and_retryable_jobs_when_runnable_test() {
  test_db.with_database(fn(connection) {
    let now = timestamp.system_time()
    let later = timestamp.add(now, duration.milliseconds(75))
    let contract = success_worker("workers.delayed")
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 2, poll_interval_ms: 25)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)
    let scheduled_options =
      job.with_schedule(job.default_enqueue_options(), job.At(later))

    let assert Ok(scheduled) =
      kairos.enqueue_with(
        kairos_config,
        contract,
        ExampleArgs(name: "scheduled"),
        scheduled_options,
      )
    let retryable =
      insert_job(
        connection,
        "workers.delayed",
        "retryable",
        job.Retryable,
        1,
        3,
        later,
      )
    let job.EnqueuedJob(id: scheduled_id, ..) = scheduled
    let job_store.PersistedJob(id: retryable_id, ..) = retryable

    let scheduled_completed =
      wait_for_completed_job(connection, scheduled_id, 120)
    let retryable_completed =
      wait_for_completed_job(connection, retryable_id, 120)
    let job_store.PersistedJob(state: scheduled_state, ..) = scheduled_completed
    let job_store.PersistedJob(state: retryable_state, ..) = retryable_completed

    assert scheduled_state == job.Completed
    assert retryable_state == job.Completed

    stop_process(started.pid)
  })
}

pub fn poller_resumes_after_queue_supervisor_restart_test() {
  test_db.with_database(fn(connection) {
    let contract = success_worker("workers.restart")
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 1, poll_interval_ms: 25)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)
    let runtime = started.data

    let assert Ok(original_poller_pid) =
      supervision.queue_poller_pid(runtime, "default")

    kill_process(original_poller_pid, "test restart")

    let restarted_poller_pid =
      wait_for_new_poller_pid(runtime, "default", original_poller_pid, 80)
    let assert Ok(enqueued) =
      kairos.enqueue(kairos_config, contract, ExampleArgs(name: "restart"))
    let job.EnqueuedJob(id:, ..) = enqueued

    let completed = wait_for_completed_job(connection, id, 80)
    let job_store.PersistedJob(state:, ..) = completed

    assert process.is_alive(restarted_poller_pid)
    assert restarted_poller_pid != original_poller_pid
    assert state == job.Completed

    stop_process(started.pid)
  })
}

pub fn poller_does_not_dispatch_running_job_twice_test() {
  test_db.with_database(fn(connection) {
    let contract = slow_worker("workers.slow", 125)
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 1, poll_interval_ms: 25)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)

    let assert Ok(enqueued) =
      kairos.enqueue(kairos_config, contract, ExampleArgs(name: "slow"))
    let job.EnqueuedJob(id:, ..) = enqueued

    let completed = wait_for_completed_job(connection, id, 120)
    let job_store.PersistedJob(state:, attempt:, ..) = completed

    assert state == job.Completed
    assert attempt == 1

    stop_process(started.pid)
  })
}

fn success_worker(name: String) -> worker.Worker(ExampleArgs) {
  worker.new(
    name,
    fn(args) {
      let ExampleArgs(name:) = args
      name
    },
    fn(payload) { Ok(ExampleArgs(name: payload)) },
    fn(_args) { worker.Success },
    job.default_enqueue_options(),
  )
}

fn slow_worker(name: String, duration_ms: Int) -> worker.Worker(ExampleArgs) {
  worker.new(
    name,
    fn(args) {
      let ExampleArgs(name:) = args
      name
    },
    fn(payload) { Ok(ExampleArgs(name: payload)) },
    fn(_args) {
      process.sleep(duration_ms)
      worker.Success
    },
    job.default_enqueue_options(),
  )
}

fn insert_job(
  connection: pog.Connection,
  worker_name: String,
  payload: String,
  state: job.JobState,
  attempt: Int,
  max_attempts: Int,
  scheduled_at: timestamp.Timestamp,
) -> job_store.PersistedJob {
  let assert Ok(inserted) =
    job_store.insert(
      connection,
      job_store.JobInsert(
        worker_name: worker_name,
        payload: payload,
        state: state,
        queue_name: "default",
        priority: 0,
        attempt: attempt,
        max_attempts: max_attempts,
        unique_key: None,
        errors: [],
        scheduled_at: scheduled_at,
        attempted_at: None,
        completed_at: None,
        discarded_at: None,
        cancelled_at: None,
      ),
    )

  inserted
}

fn wait_for_completed_job(
  connection: pog.Connection,
  id: String,
  remaining_attempts: Int,
) -> job_store.PersistedJob {
  let assert Ok(Some(stored)) = job_store.fetch(connection, id)
  let job_store.PersistedJob(state:, ..) = stored

  case state, remaining_attempts {
    job.Completed, _ -> stored
    job.Discarded, _ ->
      panic as { "job " <> id <> " was discarded while waiting for completion" }
    job.Cancelled, _ ->
      panic as { "job " <> id <> " was cancelled while waiting for completion" }
    _, 0 -> panic as { "timed out waiting for job " <> id <> " to complete" }
    _, _ -> {
      process.sleep(25)
      wait_for_completed_job(connection, id, remaining_attempts - 1)
    }
  }
}

fn wait_for_new_poller_pid(
  runtime: supervision.Runtime,
  queue_name: String,
  previous_pid: process.Pid,
  remaining_attempts: Int,
) -> process.Pid {
  case supervision.queue_poller_pid(runtime, queue_name), remaining_attempts {
    Ok(current_pid), _ if current_pid != previous_pid -> current_pid
    _, 0 ->
      panic as {
        "timed out waiting for poller restart on queue " <> queue_name
      }
    _, _ -> {
      process.sleep(25)
      wait_for_new_poller_pid(
        runtime,
        queue_name,
        previous_pid,
        remaining_attempts - 1,
      )
    }
  }
}

fn stop_process(pid: process.Pid) -> Nil {
  process.unlink(pid)
  process.send_abnormal_exit(pid, "test shutdown")
  process.sleep(25)
}

fn kill_process(pid: process.Pid, reason: String) -> Nil {
  process.unlink(pid)
  process.send_abnormal_exit(pid, reason)
  process.sleep(25)
}
