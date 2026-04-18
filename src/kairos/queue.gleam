import gleam/string

pub type QueueError {
  BlankName
  NonPositiveConcurrency
  NonPositivePollInterval
}

pub opaque type Queue {
  Queue(name: String, concurrency: Int, poll_interval_ms: Int)
}

pub fn new(
  name name: String,
  concurrency concurrency: Int,
  poll_interval_ms poll_interval_ms: Int,
) -> Result(Queue, QueueError) {
  case string.trim(name) {
    "" -> Error(BlankName)
    _ if concurrency <= 0 -> Error(NonPositiveConcurrency)
    _ if poll_interval_ms <= 0 -> Error(NonPositivePollInterval)
    trimmed_name ->
      Ok(Queue(
        name: trimmed_name,
        concurrency: concurrency,
        poll_interval_ms: poll_interval_ms,
      ))
  }
}

pub fn name(queue: Queue) -> String {
  let Queue(name:, ..) = queue
  name
}

pub fn concurrency(queue: Queue) -> Int {
  let Queue(concurrency:, ..) = queue
  concurrency
}

pub fn poll_interval_ms(queue: Queue) -> Int {
  let Queue(poll_interval_ms:, ..) = queue
  poll_interval_ms
}
