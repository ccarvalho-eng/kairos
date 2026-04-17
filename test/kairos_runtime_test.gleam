import gleam/erlang/process
import gleam/list
import gleam/otp/static_supervisor
import kairos
import kairos/config
import kairos/runtime
import pog

pub fn queue_config_rejects_duplicate_names_test() {
  let connection = test_connection()
  let assert Ok(first_queue) =
    config.queue(name: "default", concurrency: 10, poll_interval_ms: 1000)
  let assert Ok(second_queue) =
    config.queue(name: "default", concurrency: 5, poll_interval_ms: 500)

  let assert Error(config.DuplicateQueueName("default")) =
    config.new(connection: connection, queues: [first_queue, second_queue])
}

pub fn queue_config_preserves_typed_definitions_test() {
  let assert Ok(config) = sample_config()

  let queue_names =
    config.queues(config)
    |> list.map(config.queue_name)

  assert queue_names == ["default", "mailers"]
  assert config.queues(config) |> list.map(config.queue_concurrency) == [10, 3]
  assert config.queues(config) |> list.map(config.queue_poll_interval_ms)
    == [
      1000,
      2000,
    ]
}

pub fn start_builds_queue_supervisors_and_stub_processes_test() {
  let assert Ok(config) = sample_config()
  let assert Ok(started) = kairos.start(config)
  let runtime = started.data

  assert process.is_alive(started.pid)
  assert runtime.queue_names(runtime) == ["default", "mailers"]
  assert runtime.has_queue(runtime, "default")
  assert runtime.has_queue(runtime, "mailers")

  let assert Ok(root_pid) = runtime.root_pid(runtime)
  let assert Ok(default_supervisor) =
    runtime.queue_supervisor_pid(runtime, "default")
  let assert Ok(default_worker) = runtime.queue_worker_pid(runtime, "default")
  let assert Ok(default_poller) = runtime.queue_poller_pid(runtime, "default")

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

  let assert Ok(root_pid) = process.named(config.root_name(config))
  let assert [default_queue, ..] = config.queues(config)
  let assert Ok(default_queue_pid) =
    process.named(config.queue_supervisor_name(default_queue))

  assert process.is_alive(root_pid)
  assert process.is_alive(default_queue_pid)

  process.send_exit(parent.pid)
}

fn sample_config() -> Result(config.Config, config.ConfigError) {
  let connection = test_connection()
  let assert Ok(default_queue) =
    config.queue(name: "default", concurrency: 10, poll_interval_ms: 1000)
  let assert Ok(mailers_queue) =
    config.queue(name: "mailers", concurrency: 3, poll_interval_ms: 2000)

  config.new(connection: connection, queues: [default_queue, mailers_queue])
}

fn test_connection() -> pog.Connection {
  pog.named_connection(process.new_name("kairos-test-pool"))
}
