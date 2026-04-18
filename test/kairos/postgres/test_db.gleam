import envoy
import gleam/erlang/process
import gleam/otp/actor
import gleam/time/timestamp
import kairos/migration
import pog

pub fn with_database(run: fn(pog.Connection) -> Nil) -> Nil {
  let name = process.new_name("kairos_postgres_test")
  let database_url = test_database_url()

  let assert Ok(config) = pog.url_config(name, database_url)
    as "Expected a valid PostgreSQL URL for the Kairos test database. Set KAIROS_TEST_DATABASE_URL to override the local default."
  let assert Ok(actor.Started(pid: pid, data: connection)) = pog.start(config)

  wait_for_connection(connection, 20)
  reset_schema(connection)
  run(connection)
  process.send_exit(pid)
}

pub fn to_postgres_precision(
  timestamp: timestamp.Timestamp,
) -> timestamp.Timestamp {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)

  timestamp.from_unix_seconds_and_nanoseconds(
    seconds,
    { nanoseconds / 1000 } * 1000,
  )
}

fn test_database_url() -> String {
  case envoy.get("KAIROS_TEST_DATABASE_URL") {
    Ok(url) -> url
    Error(_) ->
      "postgresql://postgres:postgres@localhost:5432/kairos_test?sslmode=disable"
  }
}

fn wait_for_connection(connection: pog.Connection, remaining: Int) -> Nil {
  case pog.query("SELECT 1") |> pog.execute(connection) {
    Ok(_) -> Nil
    Error(_) ->
      case remaining {
        0 -> {
          let assert Ok(_) = pog.query("SELECT 1") |> pog.execute(connection)
          Nil
        }
        _ -> {
          process.sleep(50)
          wait_for_connection(connection, remaining - 1)
        }
      }
  }
}

fn reset_schema(connection: pog.Connection) -> Nil {
  [
    "DROP TRIGGER IF EXISTS kairos_jobs_set_updated_at ON kairos_jobs",
    "DROP FUNCTION IF EXISTS kairos_touch_updated_at()",
    "DROP TABLE IF EXISTS kairos_jobs",
  ]
  |> execute_statements(connection)

  execute_statements(
    migration.initial_migration() |> migration.statements,
    connection,
  )
}

fn execute_statements(
  statements: List(String),
  connection: pog.Connection,
) -> Nil {
  case statements {
    [] -> Nil
    [statement, ..rest] -> {
      let assert Ok(_) = pog.query(statement) |> pog.execute(connection)
      execute_statements(rest, connection)
    }
  }
}
