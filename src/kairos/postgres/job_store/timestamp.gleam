import gleam/option.{type Option, None, Some}
import gleam/time/timestamp

@internal
pub fn from_microseconds(microseconds: Int) -> timestamp.Timestamp {
  let seconds = microseconds / 1_000_000
  let nanoseconds = { microseconds % 1_000_000 } * 1000
  timestamp.from_unix_seconds_and_nanoseconds(seconds, nanoseconds)
}

@internal
pub fn option_from_microseconds(
  microseconds: Option(Int),
) -> Option(timestamp.Timestamp) {
  case microseconds {
    Some(value) -> Some(from_microseconds(value))
    None -> None
  }
}
