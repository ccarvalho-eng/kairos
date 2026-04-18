import gleam/list
import kairos/queue
import pog

pub type ConfigError {
  EmptyQueues
  DuplicateQueueName(String)
}

pub opaque type Config {
  Config(connection: pog.Connection, queues: List(queue.Queue))
}

pub fn new(
  connection connection: pog.Connection,
  queues queues: List(queue.Queue),
) -> Result(Config, ConfigError) {
  case queues {
    [] -> Error(EmptyQueues)
    _ -> {
      case find_duplicate_queue_name(queues, seen: []) {
        Ok(Nil) -> Ok(Config(connection: connection, queues: queues))
        Error(queue_name) -> Error(DuplicateQueueName(queue_name))
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
