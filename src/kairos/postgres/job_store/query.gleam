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
  RETURNING
    id::TEXT,
    worker_name,
    payload,
    state,
    queue_name,
    priority,
    attempt,
    max_attempts,
    unique_key,
    errors,
    (EXTRACT(EPOCH FROM scheduled_at) * 1000000)::BIGINT,
    CASE
      WHEN attempted_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM attempted_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN completed_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM completed_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN discarded_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM discarded_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN cancelled_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM cancelled_at) * 1000000)::BIGINT
    END,
    (EXTRACT(EPOCH FROM inserted_at) * 1000000)::BIGINT,
    (EXTRACT(EPOCH FROM updated_at) * 1000000)::BIGINT
  "
}

@internal
pub fn fetch() -> String {
  "
  SELECT
    id::TEXT,
    worker_name,
    payload,
    state,
    queue_name,
    priority,
    attempt,
    max_attempts,
    unique_key,
    errors,
    (EXTRACT(EPOCH FROM scheduled_at) * 1000000)::BIGINT,
    CASE
      WHEN attempted_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM attempted_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN completed_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM completed_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN discarded_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM discarded_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN cancelled_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM cancelled_at) * 1000000)::BIGINT
    END,
    (EXTRACT(EPOCH FROM inserted_at) * 1000000)::BIGINT,
    (EXTRACT(EPOCH FROM updated_at) * 1000000)::BIGINT
  FROM kairos_jobs
  WHERE id = $1
  "
}

@internal
pub fn fetch_available() -> String {
  "
  SELECT
    id::TEXT,
    worker_name,
    payload,
    state,
    queue_name,
    priority,
    attempt,
    max_attempts,
    unique_key,
    errors,
    (EXTRACT(EPOCH FROM scheduled_at) * 1000000)::BIGINT,
    CASE
      WHEN attempted_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM attempted_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN completed_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM completed_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN discarded_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM discarded_at) * 1000000)::BIGINT
    END,
    CASE
      WHEN cancelled_at IS NULL THEN NULL
      ELSE (EXTRACT(EPOCH FROM cancelled_at) * 1000000)::BIGINT
    END,
    (EXTRACT(EPOCH FROM inserted_at) * 1000000)::BIGINT,
    (EXTRACT(EPOCH FROM updated_at) * 1000000)::BIGINT
  FROM kairos_jobs
  WHERE state IN ('pending', 'scheduled', 'retryable')
    AND scheduled_at <= $1
  ORDER BY priority DESC, scheduled_at ASC, inserted_at ASC
  LIMIT $2
  "
}
