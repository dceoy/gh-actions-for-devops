# Commands and Guidelines for gh-actions-for-devops

## Build and Lint Commands

- **Shell linting**: `shellcheck githook/*.sh`
- **GitHub Actions linting**: `find .github/workflows -name "*.yml" -o -name "*.yaml" | xargs actionlint`
- **GitHub Actions scanning**: `zizmor --fix=safe .github/workflows`
- **YAML linting**: `find .github/workflows -name "*.yml" | xargs yamllint -d '{"extends": "relaxed", "rules": {"line-length": "disable"}}'`
- **Go formatting and linting**: `golangci-lint fmt -E gofumpt -E goimports && golangci-lint run --fix && govulncheck ./... && gosec ./...`
- **Terraform formatting and linting**: `terraform fmt -recursive . && terragrunt hclfmt --diff && tflint --recursive`
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

- Run `./githook/auto-format-and-lint.sh` before committing changes
- Workflows stored at `.github/workflows/` with symlink at `workflows/`

## Serena MCP Usage (Prioritize When Available)

- **If Serena MCP is available, use it first.** Treat Serena MCP tools as the primary interface over local commands or ad-hoc scripts.
- **Glance at the Serena MCP docs/help before calling a tool** to confirm tool names, required args, and limits.
- **Use the MCP-exposed tools for supported actions** (e.g., reading/writing files, running tasks, fetching data) instead of re-implementing workflows.
- **Never hardcode secrets.** Reference environment variables or the MCP’s configured credential store; avoid printing tokens or sensitive paths.
- **If Serena MCP isn’t enabled or lacks a needed capability, say so and propose a safe fallback.** Mention enabling it via `.mcp.json` when relevant.
- **Be explicit and reproducible.** Name the exact MCP tool and arguments you intend to use in your steps.

## Web Search Instructions

For tasks requiring web search, always use Gemini CLI (`gemini` command) instead of the built-in web search tools.
Gemini CLI is an AI workflow tool that provides reliable web search capabilities.

### Usage

```sh
# Basic search query
gemini --sandbox --prompt "WebSearch: <query>"

# Example: Search for latest news
gemini --sandbox --prompt "WebSearch: What are the latest developments in AI?"
```

### Policy

When users request information that requires web search:

1. Use `gemini --sandbox --prompt` command via terminal
2. Parse and present the Gemini response appropriately

This ensures consistent and reliable web search results through the Gemini API.

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
