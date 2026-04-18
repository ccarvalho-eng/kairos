import gleeunit
import kairos/queue

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn queue_definition_preserves_typed_values_test() {
  let assert Ok(default_queue) =
    queue.new(name: "default", concurrency: 10, poll_interval_ms: 1000)
  let assert Ok(mailers_queue) =
    queue.new(name: "mailers", concurrency: 3, poll_interval_ms: 2000)

  assert queue.name(default_queue) == "default"
  assert queue.concurrency(default_queue) == 10
  assert queue.poll_interval_ms(default_queue) == 1000

  assert queue.name(mailers_queue) == "mailers"
  assert queue.concurrency(mailers_queue) == 3
  assert queue.poll_interval_ms(mailers_queue) == 2000
}

pub fn queue_rejects_invalid_values_test() {
  assert queue.new(name: "", concurrency: 10, poll_interval_ms: 1000)
    == Error(queue.BlankName)
  assert queue.new(name: "default", concurrency: 0, poll_interval_ms: 1000)
    == Error(queue.NonPositiveConcurrency)
  assert queue.new(name: "default", concurrency: 10, poll_interval_ms: 0)
    == Error(queue.NonPositivePollInterval)
}
