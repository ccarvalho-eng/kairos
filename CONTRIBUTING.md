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

## CodeRabbit

Kairos uses repository-level CodeRabbit defaults from `.coderabbit.yaml`.

CodeRabbit is part of the review workflow, but it is not the final reviewer:

- treat CodeRabbit findings like any other review feedback and triage them by correctness, risk, and relevance
- fix or answer substantive findings before merge
- do not treat every nitpick as blocking when it does not improve correctness, maintainability, or clarity
- keep human review responsible for architecture, invariants, and merge decisions

The current defaults are tuned for signal over noise:

- automatic review is enabled on non-draft pull requests
- walkthrough noise is reduced by disabling poems, sequence diagrams, and AI-agent prompts
- source, tests, workflows, and Markdown each get targeted review instructions

If CodeRabbit becomes noisy again, adjust `.coderabbit.yaml` in version control rather than relying on ad hoc repository UI settings.
