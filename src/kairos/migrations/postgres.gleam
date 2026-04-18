//// PostgreSQL migration definitions for Kairos persistence.

import kairos/migrations/postgres/v01

pub const jobs_table = "kairos_jobs"

pub const active_unique_key_constraint = "kairos_jobs_unique_key_active_idx"

pub type Migration {
  Migration(version: Int, name: String, statements: List(String))
}

pub fn migrations() -> List(Migration) {
  [initial_migration()]
}

pub fn initial_migration() -> Migration {
  Migration(
    version: v01.version(),
    name: v01.name(),
    statements: v01.statements(),
  )
}
