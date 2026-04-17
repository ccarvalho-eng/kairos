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
  assert result_name(worker.Success) == "success"
  assert result_name(worker.Retry("retry later")) == "retry:retry later"
  assert result_name(worker.Discard("discard permanently"))
    == "discard:discard permanently"
  assert result_name(worker.Cancel("cancel execution"))
    == "cancel:cancel execution"
}

fn example_worker() -> worker.Worker(ExampleArgs) {
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
    fn(_args) { worker.Success },
    job.default_enqueue_options(),
  )
}

fn result_name(result: worker.PerformResult) -> String {
  case result {
    worker.Success -> "success"
    worker.Retry(reason) -> "retry:" <> reason
    worker.Discard(reason) -> "discard:" <> reason
    worker.Cancel(reason) -> "cancel:" <> reason
  }
}
