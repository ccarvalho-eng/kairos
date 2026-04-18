# Contributing

## Local Verification Loop

Kairos keeps the local verification loop small:

```sh
gleam format
gleam check
gleam test
```

Integration tests require PostgreSQL. By default they use:

```sh
postgresql://postgres:postgres@localhost:5432/kairos_test?sslmode=disable
```

Override that by setting `KAIROS_TEST_DATABASE_URL`.

## CI Support Policy

The baseline CI workflow in `.github/workflows/ci.yml` currently supports:

- Gleam `1.14.0`
- Erlang/OTP `27`
- Erlang/OTP `28`

This matrix is the repository’s compatibility floor for day-to-day changes. Expand the matrix only when the project intentionally broadens support, and remove versions only with an explicit support decision.

## Required Checks For `main`

Branch protection for `main` should require these checks:

- `format`
- `verify (otp 27)`
- `verify (otp 28)`

These checks cover the baseline merge gate:

- formatting stays enforced
- the codebase builds on the supported OTP matrix
- tests stay green on every supported OTP target

Keep job names stable once branch protection is enabled. If a workflow job name changes, update branch protection in the repository settings in the same maintenance window.
