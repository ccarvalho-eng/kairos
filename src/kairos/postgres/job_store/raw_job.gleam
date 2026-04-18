import gleam/dynamic/decode
import gleam/option.{type Option}

@internal
pub type RawPersistedJob {
  RawPersistedJob(
    id: String,
    worker_name: String,
    payload: String,
    state: String,
    queue_name: String,
    priority: Int,
    attempt: Int,
    max_attempts: Int,
    unique_key: Option(String),
    errors: List(String),
    scheduled_at_microseconds: Int,
    attempted_at_microseconds: Option(Int),
    completed_at_microseconds: Option(Int),
    discarded_at_microseconds: Option(Int),
    cancelled_at_microseconds: Option(Int),
    inserted_at_microseconds: Int,
    updated_at_microseconds: Int,
  )
}

@internal
pub fn decoder() -> decode.Decoder(RawPersistedJob) {
  {
    use id <- decode.field(0, decode.string)
    use worker_name <- decode.field(1, decode.string)
    use payload <- decode.field(2, decode.string)
    use state <- decode.field(3, decode.string)
    use queue_name <- decode.field(4, decode.string)
    use priority <- decode.field(5, decode.int)
    use attempt <- decode.field(6, decode.int)
    use max_attempts <- decode.field(7, decode.int)
    use unique_key <- decode.field(8, decode.optional(decode.string))
    use errors <- decode.field(9, decode.list(decode.string))
    use scheduled_at_microseconds <- decode.field(10, decode.int)
    use attempted_at_microseconds <- decode.field(
      11,
      decode.optional(decode.int),
    )
    use completed_at_microseconds <- decode.field(
      12,
      decode.optional(decode.int),
    )
    use discarded_at_microseconds <- decode.field(
      13,
      decode.optional(decode.int),
    )
    use cancelled_at_microseconds <- decode.field(
      14,
      decode.optional(decode.int),
    )
    use inserted_at_microseconds <- decode.field(15, decode.int)
    use updated_at_microseconds <- decode.field(16, decode.int)

    decode.success(RawPersistedJob(
      id: id,
      worker_name: worker_name,
      payload: payload,
      state: state,
      queue_name: queue_name,
      priority: priority,
      attempt: attempt,
      max_attempts: max_attempts,
      unique_key: unique_key,
      errors: errors,
      scheduled_at_microseconds: scheduled_at_microseconds,
      attempted_at_microseconds: attempted_at_microseconds,
      completed_at_microseconds: completed_at_microseconds,
      discarded_at_microseconds: discarded_at_microseconds,
      cancelled_at_microseconds: cancelled_at_microseconds,
      inserted_at_microseconds: inserted_at_microseconds,
      updated_at_microseconds: updated_at_microseconds,
    ))
  }
}
