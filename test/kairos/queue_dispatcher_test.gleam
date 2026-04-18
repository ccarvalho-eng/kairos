import gleam/erlang/process
import gleam/option.{Some}
import gleam/time/timestamp
import gleeunit
import kairos
import kairos/config
import kairos/job
import kairos/postgres/job_store
import kairos/postgres/test_db
import kairos/queue
import kairos/queue_dispatcher
import kairos/supervision
import kairos/worker

type ExampleArgs {
  ExampleArgs(name: String)
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn dispatch_claims_jobs_and_starts_supervised_runners_test() {
  test_db.with_database(fn(connection) {
    let contract = success_worker()
    let assert Ok(default_queue) =
      queue.new(name: "default", concurrency: 2, poll_interval_ms: 1000)
    let assert Ok(kairos_config) =
      config.new(connection: connection, queues: [default_queue], workers: [
        worker.register(contract),
      ])
    let assert Ok(started) = kairos.start(kairos_config)

    let args = ExampleArgs(name: "kairos")
    let assert Ok(enqueued) = kairos.enqueue(kairos_config, contract, args)
    let job.EnqueuedJob(id: id, ..) = enqueued
    let now = timestamp.system_time()

    let assert Ok(started_runner_pids) =
      queue_dispatcher.dispatch(kairos_config, default_queue, started.data, now)

    let assert [runner_pid] = started_runner_pids
    assert process.is_alive(runner_pid)

    process.sleep(50)

    let assert Ok(Some(stored)) = job_store.fetch(connection, id)
    let job_store.PersistedJob(state: state, completed_at: completed_at, ..) =
      stored

    assert state == job.Completed
    assert completed_at == Some(test_db.to_postgres_precision(now))

    let assert Ok(runner_supervisor_pid) =
      supervision.queue_runner_supervisor_pid(started.data, "default")
    assert process.is_alive(runner_supervisor_pid)

    process.send_exit(started.pid)
  })
}

fn success_worker() -> worker.Worker(ExampleArgs) {
  worker.new(
    "workers.success",
    fn(args) {
      let ExampleArgs(name:) = args
      name
    },
    fn(payload) { Ok(ExampleArgs(name: payload)) },
    fn(_args) { worker.Success },
    job.default_enqueue_options(),
  )
}
