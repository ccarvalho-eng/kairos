import gleam/erlang/process
import gleam/otp/static_supervisor
import gleeunit
import kairos
import kairos/config
import kairos/queue
import kairos/supervision
import pog

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn start_builds_queue_supervisors_and_stub_processes_test() {
  let assert Ok(config) = sample_config()
  let assert Ok(started) = kairos.start(config)
  let runtime = started.data

  assert process.is_alive(started.pid)
  assert supervision.queue_names(runtime) == ["default", "mailers"]
  assert supervision.has_queue(runtime, "default")
  assert supervision.has_queue(runtime, "mailers")

  let assert Ok(root_pid) = supervision.root_pid(runtime)
  let assert Ok(default_supervisor) =
    supervision.queue_supervisor_pid(runtime, "default")
  let assert Ok(default_worker) =
    supervision.queue_worker_pid(runtime, "default")
  let assert Ok(default_poller) =
    supervision.queue_poller_pid(runtime, "default")

  assert process.is_alive(root_pid)
  assert process.is_alive(default_supervisor)
  assert process.is_alive(default_worker)
  assert process.is_alive(default_poller)

  process.send_exit(started.pid)
}

pub fn supervised_starts_under_a_parent_supervisor_test() {
  let assert Ok(config) = sample_config()
  let assert Ok(parent) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(kairos.supervised(config))
    |> static_supervisor.start

  assert process.is_alive(parent.pid)

  process.send_exit(parent.pid)
}

fn sample_config() -> Result(config.Config, config.ConfigError) {
  let connection = test_connection()
  let assert Ok(default_queue) =
    queue.new(name: "default", concurrency: 10, poll_interval_ms: 1000)
  let assert Ok(mailers_queue) =
    queue.new(name: "mailers", concurrency: 3, poll_interval_ms: 2000)

  config.new(connection: connection, queues: [default_queue, mailers_queue])
}

fn test_connection() -> pog.Connection {
  pog.named_connection(process.new_name("kairos-test-pool"))
}
