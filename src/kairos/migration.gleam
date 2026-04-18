import kairos/migrations/postgres

pub type Migration =
  postgres.Migration

pub fn migrations() -> List(Migration) {
  postgres.migrations()
}

pub fn initial_migration() -> Migration {
  postgres.initial_migration()
}

pub fn version(migration: Migration) -> Int {
  let postgres.Migration(version:, ..) = migration
  version
}

pub fn name(migration: Migration) -> String {
  let postgres.Migration(name:, ..) = migration
  name
}

pub fn statements(migration: Migration) -> List(String) {
  let postgres.Migration(statements:, ..) = migration
  statements
}
