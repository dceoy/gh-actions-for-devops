# Commands and Guidelines for gh-actions-for-devops

## Build and Lint Commands
- **Python formatting and linting**: `cd src && uv run ruff format . && uv run ruff check --fix . && uv run pyright .`
- **Shell linting**: `shellcheck githook/*.sh`
- **GitHub Actions linting**: `find .github/workflows -name "*.yml" -o -name "*.yaml" | xargs actionlint`
- **YAML linting**: `find .github/workflows -name "*.yml" | xargs yamllint -d '{"extends": "relaxed", "rules": {"line-length": "disable"}}'`
- **Terraform formatting and linting**: `terraform fmt -recursive . && terragrunt hclfmt --diff && tflint --recursive`
- **Security scanning**: `trivy filesystem --scanners vuln,secret,misconfig .`
- **Build README**: `cd src && python build_readme_md.py`

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