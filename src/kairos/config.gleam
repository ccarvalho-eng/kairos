import gleam/erlang/process
import gleam/list
import gleam/string
import pog

pub type ConfigError {
  EmptyQueues
  BlankQueueName
  NonPositiveConcurrency
  NonPositivePollInterval
  DuplicateQueueName(String)
}

pub opaque type Queue {
  Queue(
    name: String,
    concurrency: Int,
    poll_interval_ms: Int,
    supervisor_name: process.Name(Nil),
    worker_name: process.Name(Nil),
    poller_name: process.Name(Nil),
  )
}

pub opaque type Config {
  Config(
    connection: pog.Connection,
    root_name: process.Name(Nil),
    queues: List(Queue),
  )
}

pub fn queue(
  name name: String,
  concurrency concurrency: Int,
  poll_interval_ms poll_interval_ms: Int,
) -> Result(Queue, ConfigError) {
  case string.trim(name) {
    "" -> Error(BlankQueueName)
    _ if concurrency <= 0 -> Error(NonPositiveConcurrency)
    _ if poll_interval_ms <= 0 -> Error(NonPositivePollInterval)
    trimmed_name -> {
      let sanitized_name = sanitize_name(trimmed_name)
      Ok(Queue(
        name: trimmed_name,
        concurrency: concurrency,
        poll_interval_ms: poll_interval_ms,
        supervisor_name: process.new_name("kairos-queue-" <> sanitized_name),
        worker_name: process.new_name("kairos-queue-worker-" <> sanitized_name),
        poller_name: process.new_name("kairos-queue-poller-" <> sanitized_name),
      ))
    }
  }
}

pub fn new(
  connection connection: pog.Connection,
  queues queues: List(Queue),
) -> Result(Config, ConfigError) {
  case queues {
    [] -> Error(EmptyQueues)
    _ -> {
      case find_duplicate_queue_name(queues, seen: []) {
        Ok(Nil) ->
          Ok(Config(
            connection: connection,
            root_name: process.new_name("kairos-root"),
            queues: queues,
          ))

        Error(queue_name) -> Error(DuplicateQueueName(queue_name))
      }
    }
  }
}

pub fn connection(config: Config) -> pog.Connection {
  let Config(connection:, ..) = config
  connection
}

pub fn root_name(config: Config) -> process.Name(Nil) {
  let Config(root_name:, ..) = config
  root_name
}

pub fn queues(config: Config) -> List(Queue) {
  let Config(queues:, ..) = config
  queues
}

pub fn queue_name(queue: Queue) -> String {
  let Queue(name:, ..) = queue
  name
}

pub fn queue_concurrency(queue: Queue) -> Int {
  let Queue(concurrency:, ..) = queue
  concurrency
}

pub fn queue_poll_interval_ms(queue: Queue) -> Int {
  let Queue(poll_interval_ms:, ..) = queue
  poll_interval_ms
}

pub fn queue_supervisor_name(queue: Queue) -> process.Name(Nil) {
  let Queue(supervisor_name:, ..) = queue
  supervisor_name
}

pub fn queue_worker_name(queue: Queue) -> process.Name(Nil) {
  let Queue(worker_name:, ..) = queue
  worker_name
}

pub fn queue_poller_name(queue: Queue) -> process.Name(Nil) {
  let Queue(poller_name:, ..) = queue
  poller_name
}

fn find_duplicate_queue_name(
  queues: List(Queue),
  seen seen: List(String),
) -> Result(Nil, String) {
  case queues {
    [] -> Ok(Nil)
    [queue, ..rest] -> {
      let queue_name = queue_name(queue)
      case list.any(seen, fn(seen_name) { seen_name == queue_name }) {
        True -> Error(queue_name)
        False -> find_duplicate_queue_name(rest, seen: [queue_name, ..seen])
      }
    }
  }
}

fn sanitize_name(name: String) -> String {
  name
  |> string.lowercase
  |> string.replace(" ", "-")
  |> string.replace("/", "-")
}
