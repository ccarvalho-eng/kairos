import gleam/list
import gleam/option.{type Option, None, Some}
import kairos/queue
import kairos/worker
import pog

pub type ConfigError {
  EmptyQueues
  DuplicateQueueName(String)
  DuplicateWorkerName(String)
}

pub opaque type Config {
  Config(
    connection: pog.Connection,
    queues: List(queue.Queue),
    workers: List(worker.RegisteredWorker),
  )
}

pub fn new(
  connection connection: pog.Connection,
  queues queues: List(queue.Queue),
  workers workers: List(worker.RegisteredWorker),
) -> Result(Config, ConfigError) {
  case queues {
    [] -> Error(EmptyQueues)
    _ -> {
      case
        find_duplicate_queue_name(queues, seen: []),
        find_duplicate_worker_name(workers, seen: [])
      {
        Ok(Nil), Ok(Nil) ->
          Ok(Config(connection: connection, queues: queues, workers: workers))
        Error(queue_name), _ -> Error(DuplicateQueueName(queue_name))
        _, Error(worker_name) -> Error(DuplicateWorkerName(worker_name))
      }
    }
  }
}

pub fn connection(config: Config) -> pog.Connection {
  let Config(connection:, ..) = config
  connection
}

pub fn queues(config: Config) -> List(queue.Queue) {
  let Config(queues:, ..) = config
  queues
}

@internal
pub fn workers(config: Config) -> List(worker.RegisteredWorker) {
  let Config(workers:, ..) = config
  workers
}

@internal
pub fn find_worker(
  config: Config,
  worker_name: String,
) -> Option(worker.RegisteredWorker) {
  find_worker_in_list(workers(config), worker_name)
}

fn find_duplicate_queue_name(
  queues: List(queue.Queue),
  seen seen: List(String),
) -> Result(Nil, String) {
  case queues {
    [] -> Ok(Nil)
    [queue_definition, ..rest] -> {
      let queue_name = queue.name(queue_definition)
      case list.any(seen, fn(seen_name) { seen_name == queue_name }) {
        True -> Error(queue_name)
        False -> find_duplicate_queue_name(rest, seen: [queue_name, ..seen])
      }
    }
  }
}

fn find_duplicate_worker_name(
  workers: List(worker.RegisteredWorker),
  seen seen: List(String),
) -> Result(Nil, String) {
  case workers {
    [] -> Ok(Nil)
    [registered_worker, ..rest] -> {
      let worker_name = worker.registered_name(registered_worker)
      case list.any(seen, fn(seen_name) { seen_name == worker_name }) {
        True -> Error(worker_name)
        False -> find_duplicate_worker_name(rest, seen: [worker_name, ..seen])
      }
    }
  }
}

fn find_worker_in_list(
  workers: List(worker.RegisteredWorker),
  worker_name: String,
) -> Option(worker.RegisteredWorker) {
  case workers {
    [] -> None
    [registered_worker, ..rest] ->
      case worker.registered_name(registered_worker) == worker_name {
        True -> Some(registered_worker)
        False -> find_worker_in_list(rest, worker_name)
      }
  }
}
