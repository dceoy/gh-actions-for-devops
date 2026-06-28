# Repository Guidelines

## Project Structure & Module Organization

This repository publishes reusable GitHub Actions workflows for DevOps tasks. Workflow definitions live in `.github/workflows/`; the `workflows` symlink points there for convenience. The generated public documentation is `README.md`, and its source template is `README.md.j2`. The README generator is a small Go module in `src/`, with production code in `src/build_readme_md.go`, tests in `src/test_build_readme_md_test.go`, and its container build in `src/Dockerfile`. Local automation and agent instructions are under `.agents/`, including `.agents/skills/local-qa`. OpenCode review subagents and the `/review-pr` command live under `.opencode/` (auto-discovered by OpenCode), converted from Anthropic's `pr-review-toolkit` plugin.

## Build, Test, and Development Commands

- `cd src && go test ./...`: run Go unit tests for the README generator.
- `cd src && go build -o build_readme_md .`: build the README generator locally.
- `cd src && ./build_readme_md`: regenerate root `README.md` from `README.md.j2` and `.github/workflows`.
- `docker compose run --rm gh-actions-for-devops-readme`: regenerate `README.md` in the containerized environment.
- `scripts/qa.sh`: run the local QA workflow defined by `.agents/skills/local-qa` after file changes.

## Coding Style & Naming Conventions

Use Go defaults: tabs from `gofmt`, idiomatic exported/unexported names, and table-driven tests where they improve clarity. Keep workflow files in kebab-case with a `.yml` extension, for example `docker-build-and-push.yml`. Prefer explicit `workflow_call` inputs and secrets, and keep action versions pinned as full commit SHAs with version comments when updating workflows.

Apply KISS, DRY, and YAGNI consistently. Keep reusable workflows small and explicit, share repeated logic only when duplication is real, and avoid inputs, jobs, or helper code that no current workflow needs. Prefer clear YAML and straightforward Go over speculative abstractions.

## Testing Guidelines

Add or update Go tests in `src/*_test.go` for generator behavior changes. Use deterministic test fixtures or stubs instead of invoking networked tools directly. For workflow changes, run `actionlint` when available and validate YAML formatting. Regenerate `README.md` whenever workflow names or descriptions change, then review the generated table.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects such as `Harden reusable workflows against injection and unmasked secrets` and Dependabot subjects such as `Bump actions/checkout from 6.0.2 to 6.0.3`. Keep commits focused and describe user-visible workflow or documentation effects. PRs should include a concise summary, mention affected workflow files, link related issues when applicable, and note local checks run. Include screenshots only for documentation rendering changes where visual layout matters.

## Security & Configuration Tips

Never pass sensitive values through reusable workflow `with:` inputs; use `secrets:` so GitHub masks them in logs. Treat BuildKit secret names and file paths as non-sensitive metadata, and put actual secret values in repository or organization secrets.
