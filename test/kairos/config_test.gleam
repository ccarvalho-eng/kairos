import gleam/erlang/process
import gleeunit
import kairos/config
import kairos/job
import kairos/queue
import kairos/worker
import pog

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn config_rejects_duplicate_queue_names_test() {
  let connection = test_connection()
  let assert Ok(first_queue) =
    queue.new(name: "default", concurrency: 10, poll_interval_ms: 1000)
  let assert Ok(second_queue) =
    queue.new(name: "default", concurrency: 5, poll_interval_ms: 500)

  let assert Error(config.DuplicateQueueName("default")) =
    config.new(
      connection: connection,
      queues: [first_queue, second_queue],
      workers: [],
    )
}

pub fn config_requires_at_least_one_queue_test() {
  let connection = test_connection()

  assert config.new(connection: connection, queues: [], workers: [])
    == Error(config.EmptyQueues)
}

pub fn config_rejects_duplicate_worker_names_test() {
  let connection = test_connection()
  let assert Ok(default_queue) =
    queue.new(name: "default", concurrency: 10, poll_interval_ms: 1000)
  let worker_one = worker.register(example_worker("mailers.email"))
  let worker_two = worker.register(example_worker("mailers.email"))

  let assert Error(config.DuplicateWorkerName("mailers.email")) =
    config.new(connection: connection, queues: [default_queue], workers: [
      worker_one,
      worker_two,
    ])
}

pub fn config_accepts_distinct_worker_names_test() {
  let connection = test_connection()
  let assert Ok(default_queue) =
    queue.new(name: "default", concurrency: 10, poll_interval_ms: 1000)
  let worker_one = worker.register(example_worker("mailers.email"))
  let worker_two = worker.register(example_worker("mailers.digest"))

  let assert Ok(_) =
    config.new(connection: connection, queues: [default_queue], workers: [
      worker_one,
      worker_two,
    ])
}

fn test_connection() -> pog.Connection {
  pog.named_connection(process.new_name("kairos-test-pool"))
}

fn example_worker(name: String) -> worker.Worker(String) {
  worker.new(
    name,
    fn(payload) { payload },
    fn(payload) { Ok(payload) },
    fn(_payload) { worker.Success },
    job.default_enqueue_options(),
  )
}
