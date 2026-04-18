import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import kairos/config
import kairos/runtime/job_runner
import kairos/runtime/queue_reaper
import kairos/supervision/name
import kairos/supervision/queue_runtime
import kairos/supervision/queue_supervisor
import kairos/supervision/registered_supervisor

pub opaque type Runtime {
  Runtime(
    root_name: process.Name(Nil),
    queues: List(queue_runtime.QueueRuntime),
    queue_map: dict.Dict(String, queue_runtime.QueueRuntime),
  )
}

pub fn start(
  config config: config.Config,
) -> Result(actor.Started(Runtime), actor.StartError) {
  let root_name = name.root_supervisor()
  let queue_pairs =
    config.queues(config)
    |> list.map(fn(queue_definition) {
      #(queue_runtime.from_queue(queue_definition), queue_definition)
    })
  let queue_runtimes =
    queue_pairs
    |> list.map(fn(pair) {
      let #(runtime_for_queue, _) = pair
      runtime_for_queue
    })
  let queue_map =
    queue_runtimes
    |> list.map(fn(runtime_for_queue) {
      #(queue_runtime.name(runtime_for_queue), runtime_for_queue)
    })
    |> dict.from_list
  let builder =
    queue_pairs
    |> list.fold(
      static_supervisor.new(static_supervisor.OneForOne),
      fn(builder, pair) {
        let #(runtime_for_queue, _) = pair
        builder
        |> static_supervisor.add(queue_supervisor.supervised(
          config: config,
          runtime: runtime_for_queue,
        ))
      },
    )

  case
    registered_supervisor.start(
      root_name,
      builder,
      "kairos root supervisor name already registered",
    )
  {
    Ok(started) ->
      Ok(actor.Started(
        pid: started.pid,
        data: Runtime(
          root_name: root_name,
          queues: queue_runtimes,
          queue_map: queue_map,
        ),
      ))

    Error(error) -> Error(error)
  }
}

pub fn supervised(config config: config.Config) -> ChildSpecification(Runtime) {
  supervision.supervisor(fn() { start(config: config) })
}

pub fn queue_names(runtime: Runtime) -> List(String) {
  let Runtime(queues:, ..) = runtime
  queues |> list.map(queue_runtime.name)
}

pub fn has_queue(runtime: Runtime, queue_name: String) -> Bool {
  let Runtime(queue_map:, ..) = runtime
  dict.has_key(queue_map, queue_name)
}

@internal
pub fn queue_supervisor_pid(
  runtime: Runtime,
  queue_name: String,
) -> Result(process.Pid, Nil) {
  use runtime_for_queue <- result.try(find_queue_runtime(runtime, queue_name))
  queue_runtime.supervisor_pid(runtime_for_queue)
}

@internal
pub fn queue_runner_supervisor_pid(
  runtime: Runtime,
  queue_name: String,
) -> Result(process.Pid, Nil) {
  use runtime_for_queue <- result.try(find_queue_runtime(runtime, queue_name))
  queue_runtime.runner_supervisor_pid(runtime_for_queue)
}

@internal
pub fn queue_runner_supervisor_name(
  runtime: Runtime,
  queue_name: String,
) -> Result(
  process.Name(factory_supervisor.Message(job_runner.RunnerArg, String)),
  Nil,
) {
  use runtime_for_queue <- result.try(find_queue_runtime(runtime, queue_name))
  Ok(queue_runtime.runner_supervisor_name(runtime_for_queue))
}

@internal
pub fn queue_poller_pid(
  runtime: Runtime,
  queue_name: String,
) -> Result(process.Pid, Nil) {
  use runtime_for_queue <- result.try(find_queue_runtime(runtime, queue_name))
  queue_runtime.poller_pid(runtime_for_queue)
}

@internal
pub fn queue_reaper_pid(
  runtime: Runtime,
  queue_name: String,
) -> Result(process.Pid, Nil) {
  use runtime_for_queue <- result.try(find_queue_runtime(runtime, queue_name))
  queue_runtime.reaper_pid(runtime_for_queue)
}

@internal
pub fn queue_reaper_name(
  runtime: Runtime,
  queue_name: String,
) -> Result(process.Name(queue_reaper.Message), Nil) {
  use runtime_for_queue <- result.try(find_queue_runtime(runtime, queue_name))
  Ok(queue_runtime.reaper_name(runtime_for_queue))
}

pub fn root_pid(runtime: Runtime) -> Result(process.Pid, Nil) {
  let Runtime(root_name:, ..) = runtime
  process.named(root_name)
}

fn find_queue_runtime(
  runtime: Runtime,
  queue_name: String,
) -> Result(queue_runtime.QueueRuntime, Nil) {
  let Runtime(queue_map:, ..) = runtime
  dict.get(queue_map, queue_name)
}
