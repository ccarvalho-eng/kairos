import gleam/list
import gleam/string
import kairos/job

pub fn version() -> Int {
  1
}

pub fn name() -> String {
  "create_jobs_table"
}

pub fn statements() -> List(String) {
  [
    "CREATE EXTENSION IF NOT EXISTS pgcrypto",
    create_jobs_table_statement(),
    create_unique_key_index_statement(),
    create_updated_at_function_statement(),
    create_updated_at_trigger_statement(),
  ]
}

fn supported_states() -> List(String) {
  [
    job.Pending,
    job.Scheduled,
    job.Executing,
    job.Retryable,
    job.Completed,
    job.Discarded,
    job.Cancelled,
  ]
  |> list.map(job.state_name)
}

fn active_unique_states() -> List(String) {
  [job.Pending, job.Scheduled, job.Executing, job.Retryable]
  |> list.map(job.state_name)
}

fn create_jobs_table_statement() -> String {
  "CREATE TABLE kairos_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_name TEXT NOT NULL,
    payload TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN (" <> quoted_csv(supported_states()) <> ")),
    queue_name TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    attempt INTEGER NOT NULL DEFAULT 0 CHECK (attempt >= 0),
    max_attempts INTEGER NOT NULL CHECK (max_attempts > 0),
    unique_key TEXT,
    errors TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    scheduled_at TIMESTAMPTZ NOT NULL,
    attempted_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    discarded_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT kairos_jobs_attempt_bounds_check CHECK (attempt <= max_attempts),
    CONSTRAINT kairos_jobs_completed_state_check CHECK (
      (state = 'completed' AND completed_at IS NOT NULL AND discarded_at IS NULL AND cancelled_at IS NULL)
      OR (state <> 'completed' AND completed_at IS NULL)
    ),
    CONSTRAINT kairos_jobs_discarded_state_check CHECK (
      (state = 'discarded' AND discarded_at IS NOT NULL AND completed_at IS NULL AND cancelled_at IS NULL)
      OR (state <> 'discarded' AND discarded_at IS NULL)
    ),
    CONSTRAINT kairos_jobs_cancelled_state_check CHECK (
      (state = 'cancelled' AND cancelled_at IS NOT NULL AND completed_at IS NULL AND discarded_at IS NULL)
      OR (state <> 'cancelled' AND cancelled_at IS NULL)
    )
  )"
}

fn create_unique_key_index_statement() -> String {
  "CREATE UNIQUE INDEX kairos_jobs_unique_key_active_idx
  ON kairos_jobs (unique_key)
  WHERE unique_key IS NOT NULL
    AND state IN (" <> quoted_csv(active_unique_states()) <> ")"
}

fn create_updated_at_function_statement() -> String {
  "CREATE OR REPLACE FUNCTION kairos_touch_updated_at()
  RETURNS TRIGGER AS $$
  BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql"
}

fn create_updated_at_trigger_statement() -> String {
  "CREATE TRIGGER kairos_jobs_set_updated_at
  BEFORE UPDATE ON kairos_jobs
  FOR EACH ROW
  EXECUTE FUNCTION kairos_touch_updated_at()"
}

fn quoted_csv(values: List(String)) -> String {
  values
  |> list.map(fn(value) { "'" <> value <> "'" })
  |> string.join(", ")
}
