import gleam/erlang/process
import gleeunit
import kairos/config
import kairos/queue
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
    config.new(connection: connection, queues: [first_queue, second_queue])
}

pub fn config_requires_at_least_one_queue_test() {
  let connection = test_connection()

  assert config.new(connection: connection, queues: [])
    == Error(config.EmptyQueues)
}

fn test_connection() -> pog.Connection {
  pog.named_connection(process.new_name("kairos-test-pool"))
}
