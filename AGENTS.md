# Repository Guidelines

## Project Structure & Module Organization

- `.github/workflows/` contains reusable GitHub Actions workflows; each file is a `workflow_call` unit intended to be consumed from other repositories.
- `workflows/` is a symlink to `.github/workflows/` for compatibility.
- `src/build_readme_md.go` is the Go utility that discovers reusable workflows and regenerates documentation.
- `README.md.j2` is the template; `README.md` is generated output.
- `Dockerfile` and `compose.yml` provide a containerized way to run the README generator.

## Build, Test, and Development Commands

- `go run ./src/build_readme_md.go`: regenerate `README.md` from workflow metadata.
- `go build -o src/build_readme_md ./src/build_readme_md.go`: build the local generator binary.
- `docker compose run --rm gh-actions-for-devops-readme`: run the generator in Docker.
- `./scripts/qa.sh`: run repository QA (formatting, linting, and security checks for detected file types).
- `go test ./...`: run Go tests (add tests when introducing new Go logic).

## Coding Style & Naming Conventions

- Follow idiomatic Go naming: `CamelCase` for exported identifiers, `camelCase` for internal identifiers.
- Respect `.golangci.yml`; formatting and imports are enforced via `gofumpt` and `goimports` through `golangci-lint`.
- Name workflow files in kebab-case and keep names action-oriented (for example, `terraform-lint-and-scan.yml`).
- In workflow YAML, pin third-party actions to full commit SHAs.

## Testing Guidelines

- Place Go tests next to source files using `*_test.go` naming.
- For workflow changes, run `./scripts/qa.sh`; it validates workflows with tools like `actionlint`, `yamllint`, `zizmor`, and `checkov` when available.
- Ensure `go mod tidy` does not leave diffs in `go.mod` or `go.sum`.

## Commit & Pull Request Guidelines

- Match repository history: short, imperative, sentence-case subjects (for example, `Fix ...`, `Add ...`, `Remove ...`).
- Dependency updates should follow the existing `Bump <dep> from <old> to <new>` pattern.
- Keep PRs focused and include: concise summary, affected workflow paths, linked issue/context, and regenerated `README.md` when workflow inventory changes.
- Branch names use appropriate prefixes on creation (e.g., `feature/short-description`, `bugfix/short-description`).
- When instructed to create a PR, create it as a draft with appropriate labels by default.

## Git Workflow

### Pre-Commit Checklist

**IMPORTANT**: Run the following on each change before committing:

1. **format and lint**: Use the `local-qa` skill.
2. **test**: Execute relevant test suites for modified code (if applicable).
3. **security scan** (periodically): `trivy filesystem --scanners vuln,secret,misconfig .`

### Workflow Organization

- Workflows stored at `.github/workflows/` with symlink at `workflows/`

## Code Design Principles

Always prefer the simplest design that works.

- **KISS**: Choose straightforward solutions and avoid unnecessary abstraction.
- **DRY**: Remove duplication when it improves clarity and maintainability.
- **YAGNI**: Do not add features, hooks, or flexibility until they are needed.
- **SOLID/Clean Code**: Apply these as tools, only when they keep the design simpler and easier to change.

## Development Methodology

Keep delivery incremental, test-backed, and easy to review.

- Make small, safe, reversible changes.
- Prefer `Red -> Green -> Refactor`.
- Do not mix feature work and refactoring in the same commit.
- Refactor when it improves clarity or removes real duplication (Rule of Three).
- Keep tests fast, focused, and self-validating.
