import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import gleam/string
import gleam/time/timestamp
import kairos/config
import kairos/postgres/job_store
import kairos/runtime/job_runner
import kairos/runtime/queue_dispatch

pub type Message {
  Tick
}

pub type PollError {
  ClaimFailed(job_store.StoreError)
  DispatchFailed(queue_dispatch.DispatchClaimedError)
}

type State {
  State(
    name: process.Name(Message),
    config: config.Config,
    queue_name: String,
    concurrency: Int,
    poll_interval_ms: Int,
    runner_supervisor_name: process.Name(
      factory_supervisor.Message(job_runner.RunnerArg, String),
    ),
  )
}

@internal
pub fn start(
  name name: process.Name(Message),
  config config: config.Config,
  queue_name queue_name: String,
  concurrency concurrency: Int,
  poll_interval_ms poll_interval_ms: Int,
  runner_supervisor_name runner_supervisor_name: process.Name(
    factory_supervisor.Message(job_runner.RunnerArg, String),
  ),
) -> Result(actor.Started(Nil), actor.StartError) {
  actor.new(State(
    name: name,
    config: config,
    queue_name: queue_name,
    concurrency: concurrency,
    poll_interval_ms: poll_interval_ms,
    runner_supervisor_name: runner_supervisor_name,
  ))
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) {
    schedule_next_tick(name, poll_interval_ms)
    actor.Started(pid: started.pid, data: Nil)
  })
}

@internal
pub fn supervised(
  name name: process.Name(Message),
  config config: config.Config,
  queue_name queue_name: String,
  concurrency concurrency: Int,
  poll_interval_ms poll_interval_ms: Int,
  runner_supervisor_name runner_supervisor_name: process.Name(
    factory_supervisor.Message(job_runner.RunnerArg, String),
  ),
) -> ChildSpecification(Nil) {
  supervision.worker(fn() {
    start(
      name: name,
      config: config,
      queue_name: queue_name,
      concurrency: concurrency,
      poll_interval_ms: poll_interval_ms,
      runner_supervisor_name: runner_supervisor_name,
    )
  })
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Tick -> {
      let State(name:, queue_name:, poll_interval_ms:, ..) = state

      case poll_queue(state, timestamp.system_time()) {
        Ok(_) -> Nil
        Error(error) ->
          io.println(
            "kairos poller failed for queue "
            <> queue_name
            <> ": "
            <> string.inspect(error),
          )
      }

      schedule_next_tick(name, poll_interval_ms)
      actor.continue(state)
    }
  }
}

fn poll_queue(state: State, now: timestamp.Timestamp) -> Result(Int, PollError) {
  let State(
    config: config,
    queue_name: queue_name,
    concurrency: concurrency,
    runner_supervisor_name: runner_supervisor_name,
    ..,
  ) = state

  let claimed_jobs =
    job_store.claim_available(
      config.connection(config),
      queue_name,
      now,
      concurrency,
    )
    |> result.map_error(ClaimFailed)
  use claimed_jobs <- result.try(claimed_jobs)

  case claimed_jobs {
    [] -> Ok(0)
    _ ->
      queue_dispatch.dispatch_claimed(
        config,
        queue_name,
        runner_supervisor_name,
        claimed_jobs,
        now,
      )
      |> result.map(list.length)
      |> result.map_error(DispatchFailed)
  }
}

fn schedule_next_tick(name: process.Name(Message), delay_ms: Int) -> Nil {
  process.send_after(process.named_subject(name), delay_ms, Tick)
  Nil
}
