# Commands and Guidelines for gh-actions-for-devops

## Build and Lint Commands

- **Linting and formatting**: Use the `local-qa` skill (do not run individual lint/format commands directly).
- **Security scanning**: `trivy filesystem --scanners vuln,secret,misconfig .`
- **Build README**: `go run ./src/build_readme_md.go`

## Code Style Guidelines

- **Python**: Google docstring style; line length 88; strict type checking with pyright
- **Formatting**: Use ruff for Python code formatting and linting
- **Imports**: Use absolute imports, organized by stdlib, 3rd party, local
- **Error handling**: Use appropriate exceptions with context; prefer specific over general exceptions
- **Path handling**: Use pathlib.Path instead of string manipulation for file paths
- **Naming conventions**: snake_case for variables/functions, PascalCase for classes
- **Logging**: Use the logging module with appropriate log levels
- **Security**: Avoid hardcoded secrets; use environment variables or secret management
- **CI**: GitHub Actions workflows in `.github/workflows/` for automation

## Git Workflow

### Pre-Commit Checklist

**IMPORTANT**: Run the following on each change before committing:

1. **format and lint**: Use the `local-qa` skill.
2. **test**: Execute relevant test suites for modified code (if applicable).
3. **security scan** (periodically): `trivy filesystem --scanners vuln,secret,misconfig .`

### Workflow Organization

- Workflows stored at `.github/workflows/` with symlink at `workflows/`

## Commit & Pull Request Guidelines

- Commit messages are short, imperative, sentence-case.
- Branch names use appropriate prefixes on creation (e.g., `feature/short-description`, `bugfix/short-description`).
- PRs should include: a clear summary, relevant context or linked issue.
- When instructed to create a PR, create it as a draft with appropriate labels by default.

## Code Design Principles

Follow Robert C. Martin's SOLID and Clean Code principles:

### SOLID Principles

1. **SRP (Single Responsibility)**: One reason to change per class; separate concerns (e.g., storage vs formatting vs calculation)
2. **OCP (Open/Closed)**: Open for extension, closed for modification; use polymorphism over if/else chains
3. **LSP (Liskov Substitution)**: Subtypes must be substitutable for base types without breaking expectations
4. **ISP (Interface Segregation)**: Many specific interfaces over one general; no forced unused dependencies
5. **DIP (Dependency Inversion)**: Depend on abstractions, not concretions; inject dependencies

### Clean Code Practices

- **Naming**: Intention-revealing, pronounceable, searchable names (`daysSinceLastUpdate` not `d`)
- **Functions**: Small, single-task, verb names, 0-3 args, extract complex logic
- **Classes**: Follow SRP, high cohesion, descriptive names
- **Error Handling**: Exceptions over error codes, no null returns, provide context, try-catch-finally first
- **Testing**: TDD, one assertion/test, FIRST principles (Fast, Independent, Repeatable, Self-validating, Timely), Arrange-Act-Assert pattern
- **Code Organization**: Variables near usage, instance vars at top, public then private functions, conceptual affinity
- **Comments**: Self-documenting code preferred, explain "why" not "what", delete commented code
- **Formatting**: Consistent, vertical separation, 88-char limit, team rules override preferences
- **General**: DRY, KISS, YAGNI, Boy Scout Rule, fail fast

## Development Methodology

Follow Martin Fowler's Refactoring, Kent Beck's Tidy Code, and t_wada's TDD principles:

### Core Philosophy

- **Small, safe changes**: Tiny, reversible, testable modifications
- **Separate concerns**: Never mix features with refactoring
- **Test-driven**: Tests provide safety and drive design
- **Economic**: Only refactor when it aids immediate work

### TDD Cycle

1. **Red** → Write failing test
2. **Green** → Minimum code to pass
3. **Refactor** → Clean without changing behavior
4. **Commit** → Separate commits for features vs refactoring

### Practices

- **Before**: Create TODOs, ensure coverage, identify code smells
- **During**: Test-first, small steps, frequent tests, two hats rule
- **Refactoring**: Extract function/variable, rename, guard clauses, remove dead code, normalize symmetries
- **TDD Strategies**: Fake it, obvious implementation, triangulation

### When to Apply

- Rule of Three (3rd duplication)
- Preparatory (before features)
- Comprehension (as understanding grows)
- Opportunistic (daily improvements)

### Key Rules

- One assertion per test
- Separate refactoring commits
- Delete redundant tests
- Human-readable code first

> "Make the change easy, then make the easy change." - Kent Beck
