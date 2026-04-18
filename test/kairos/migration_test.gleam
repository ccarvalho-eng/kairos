import gleeunit
import kairos/migration

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn migration_exposes_initial_postgres_migration_test() {
  let initial = migration.initial_migration()

  assert migration.version(initial) == 1
  assert migration.name(initial) == "create_jobs_table"
  assert migration.migrations() == [initial]
  assert migration.statements(initial) != []
}
