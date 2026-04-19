@internal
pub fn insert() -> String {
  "
  INSERT INTO kairos_jobs (
    worker_name,
    payload,
    state,
    queue_name,
    priority,
    attempt,
    max_attempts,
    unique_key,
    errors,
    scheduled_at,
    attempted_at,
    completed_at,
    discarded_at,
    cancelled_at
  )
  VALUES (
    $1::TEXT,
    $2::TEXT,
    $3::TEXT,
    $4::TEXT,
    $5::INTEGER,
    $6::INTEGER,
    $7::INTEGER,
    $8::TEXT,
    $9::TEXT[],
    $10::TIMESTAMPTZ,
    $11::TIMESTAMPTZ,
    $12::TIMESTAMPTZ,
    $13::TIMESTAMPTZ,
    $14::TIMESTAMPTZ
  )
  " <> returned_columns("kairos_jobs")
}

@internal
pub fn fetch() -> String {
  "
  SELECT
  " <> selected_columns("kairos_jobs") <> "
  FROM kairos_jobs
  WHERE id = $1
  "
}

@internal
pub fn fetch_for_update() -> String {
  "
  SELECT
  " <> selected_columns("kairos_jobs") <> "
  FROM kairos_jobs
  WHERE id = $1
  FOR UPDATE
  "
}

@internal
pub fn list_filtered() -> String {
  "
  SELECT
  " <> selected_columns("kairos_jobs") <> "
  FROM kairos_jobs
  WHERE ($1::TEXT IS NULL OR id = ($1::TEXT)::UUID)
    AND ($2::TEXT IS NULL OR queue_name = $2)
    AND ($3::TEXT IS NULL OR worker_name = $3)
    AND (
      COALESCE(array_length($4::TEXT[], 1), 0) = 0
      OR state = ANY($4::TEXT[])
    )
  ORDER BY updated_at DESC, inserted_at DESC, id DESC
  LIMIT $5
  "
}

@internal
pub fn fetch_available() -> String {
  "
  SELECT
  " <> selected_columns("kairos_jobs") <> "
  FROM kairos_jobs
  WHERE state IN ('pending', 'scheduled', 'retryable')
    AND scheduled_at <= $1
    AND attempt < max_attempts
  ORDER BY priority DESC, scheduled_at ASC, inserted_at ASC
  LIMIT $2
  "
}

@internal
pub fn fetch_stale_executing() -> String {
  "
  WITH stale AS (
    SELECT id
    FROM kairos_jobs
    WHERE queue_name = $1
      AND state = 'executing'
      AND attempted_at IS NOT NULL
      AND attempted_at <= $2
    ORDER BY attempted_at ASC, inserted_at ASC
    LIMIT $3
    FOR UPDATE SKIP LOCKED
  )
  SELECT
  " <> selected_columns("kairos_jobs") <> "
  FROM kairos_jobs
  INNER JOIN stale
    ON kairos_jobs.id = stale.id
  ORDER BY kairos_jobs.attempted_at ASC, kairos_jobs.inserted_at ASC
  "
}

@internal
pub fn claim_available() -> String {
  "
  WITH claimable AS (
    SELECT id
    FROM kairos_jobs
    WHERE queue_name = $1
      AND state IN ('pending', 'scheduled', 'retryable')
      AND scheduled_at <= $2
      AND attempt < max_attempts
    ORDER BY priority DESC, scheduled_at ASC, inserted_at ASC
    LIMIT $3
    FOR UPDATE SKIP LOCKED
  )
  UPDATE kairos_jobs
  SET
    state = 'executing',
    attempt = kairos_jobs.attempt + 1,
    attempted_at = $2
  FROM claimable
  WHERE kairos_jobs.id = claimable.id
  " <> returned_columns("kairos_jobs")
}

@internal
pub fn complete() -> String {
  "
  UPDATE kairos_jobs
  SET
    state = 'completed',
    completed_at = $2
  WHERE id = $1
    AND state = 'executing'
  " <> returned_columns("kairos_jobs")
}

@internal
pub fn retry() -> String {
  "
  UPDATE kairos_jobs
  SET
    state = 'retryable',
    scheduled_at = $2,
    errors = array_append(kairos_jobs.errors, $3::TEXT)
  WHERE id = $1
    AND state = 'executing'
  " <> returned_columns("kairos_jobs")
}

@internal
pub fn discard() -> String {
  "
  UPDATE kairos_jobs
  SET
    state = 'discarded',
    discarded_at = $2,
    errors = array_append(kairos_jobs.errors, $3::TEXT)
  WHERE id = $1
    AND state = 'executing'
  " <> returned_columns("kairos_jobs")
}

@internal
pub fn cancel() -> String {
  "
  UPDATE kairos_jobs
  SET
    state = 'cancelled',
    cancelled_at = $2,
    errors = array_append(kairos_jobs.errors, $3::TEXT)
  WHERE id = $1
    AND state = 'executing'
  " <> returned_columns("kairos_jobs")
}

@internal
pub fn cancel_before_execution() -> String {
  "
  UPDATE kairos_jobs
  SET
    state = 'cancelled',
    cancelled_at = $2,
    errors = array_append(kairos_jobs.errors, $3::TEXT)
  WHERE id = $1
    AND state IN ('pending', 'scheduled', 'retryable')
  " <> returned_columns("kairos_jobs")
}

@internal
pub fn retry_now() -> String {
  "
  UPDATE kairos_jobs
  SET
    state = 'pending',
    scheduled_at = $2,
    attempted_at = NULL,
    completed_at = NULL,
    discarded_at = NULL,
    cancelled_at = NULL,
    max_attempts = GREATEST(kairos_jobs.max_attempts, kairos_jobs.attempt + 1)
  WHERE id = $1
    AND state IN ('discarded', 'cancelled')
  " <> returned_columns("kairos_jobs")
}

fn selected_columns(table_name: String) -> String {
  "
    " <> table_name <> ".id::TEXT,
    " <> table_name <> ".worker_name,
    " <> table_name <> ".payload,
    " <> table_name <> ".state,
    " <> table_name <> ".queue_name,
    " <> table_name <> ".priority,
    " <> table_name <> ".attempt,
    " <> table_name <> ".max_attempts,
    " <> table_name <> ".unique_key,
    " <> table_name <> ".errors,
    (EXTRACT(EPOCH FROM " <> table_name <> ".scheduled_at) * 1000000)::BIGINT,
    CASE
      WHEN " <> table_name <> ".attempted_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM " <> table_name <> ".attempted_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN " <> table_name <> ".completed_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM " <> table_name <> ".completed_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN " <> table_name <> ".discarded_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM " <> table_name <> ".discarded_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN " <> table_name <> ".cancelled_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM " <> table_name <> ".cancelled_at) * 1000000)::BIGINT
    END,
    (EXTRACT(EPOCH FROM " <> table_name <> ".inserted_at) * 1000000)::BIGINT,
    (EXTRACT(EPOCH FROM " <> table_name <> ".updated_at) * 1000000)::BIGINT
  "
}

fn returned_columns(table_name: String) -> String {
  "
  RETURNING
  " <> selected_columns(table_name)
}
