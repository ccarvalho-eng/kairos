import gleeunit
import kairos/job
import kairos/worker

type ExampleArgs {
  ExampleArgs(name: String)
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn worker_contract_test() {
  let contract = example_worker()
  let args = ExampleArgs(name: "kairos")

  assert worker.name(contract) == "example"
  assert worker.default_options(contract) == job.default_enqueue_options()
  assert worker.encode(contract, args) == "kairos"
  assert worker.decode(contract, "kairos") == Ok(args)
  assert worker.perform(contract, args) == worker.Success
}

pub fn decode_error_test() {
  let contract = example_worker()

  assert worker.decode(contract, "")
    == Error(worker.DecodeError("payload cannot be empty"))
}

pub fn perform_result_variants_test() {
  let args = ExampleArgs(name: "kairos")

  assert worker.perform(success_worker(), args) == worker.Success
  assert worker.perform(retry_worker(), args) == worker.Retry("retry later")
  assert worker.perform(discard_worker(), args)
    == worker.Discard("discard permanently")
  assert worker.perform(cancel_worker(), args)
    == worker.Cancel("cancel execution")
}

fn example_worker() -> worker.Worker(ExampleArgs) {
  result_worker(worker.Success)
}

fn success_worker() -> worker.Worker(ExampleArgs) {
  result_worker(worker.Success)
}

fn retry_worker() -> worker.Worker(ExampleArgs) {
  result_worker(worker.Retry("retry later"))
}

fn discard_worker() -> worker.Worker(ExampleArgs) {
  result_worker(worker.Discard("discard permanently"))
}

fn cancel_worker() -> worker.Worker(ExampleArgs) {
  result_worker(worker.Cancel("cancel execution"))
}

fn result_worker(result: worker.PerformResult) -> worker.Worker(ExampleArgs) {
  worker.new(
    "example",
    fn(args) {
      let ExampleArgs(name:) = args
      name
    },
    fn(payload) {
      case payload {
        "" -> Error(worker.DecodeError("payload cannot be empty"))
        _ -> Ok(ExampleArgs(name: payload))
      }
    },
    fn(_args) { result },
    job.default_enqueue_options(),
  )
}
