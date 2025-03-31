# Product Context

## Why This Project Exists

The `gh-actions-for-devops` project exists to provide a collection of reusable GitHub Actions workflows for common DevOps tasks. It aims to standardize and simplify CI/CD processes across projects by offering pre-configured, well-tested workflow templates that can be easily incorporated into any GitHub repository.

## Problems It Solves

1. **Reduces Duplication**: Eliminates the need to write the same CI/CD workflows across multiple repositories.
2. **Ensures Best Practices**: Implements DevOps best practices for various technologies (Docker, Terraform, Python, etc.).
3. **Simplifies Maintenance**: Centralizes workflow maintenance, allowing updates to propagate to all consuming repositories.
4. **Standardizes Processes**: Creates consistent CI/CD processes across projects.
5. **Reduces Setup Time**: Enables quick implementation of complex CI/CD pipelines.
6. **Improves Security**: Incorporates security scanning and best practices by default.

## How It Should Work

1. **Reusable Workflows**: Each workflow file in the `.github/workflows` directory is designed to be reusable via GitHub's `workflow_call` trigger.
2. **Parameterized**: Workflows accept inputs and secrets to customize behavior while maintaining a standard structure.
3. **Self-Contained**: Each workflow handles a specific DevOps task (linting, building, scanning, deploying, etc.).
4. **Composable**: Workflows can be combined to create more complex pipelines (e.g., the CI workflow uses multiple specialized workflows).
5. **Documentation**: The README.md is automatically generated to document available workflows.
6. **Versioned**: Workflows are versioned through GitHub releases, allowing consumers to pin to specific versions.

## Key Features

1. **Docker Operations**: Building, pushing, scanning, and linting Docker images.
2. **Terraform Management**: Formatting, linting, scanning, and deploying with Terraform.
3. **Code Quality**: Linting and formatting for various languages (Python, R, Shell, YAML, JSON, TOML).
4. **Security Scanning**: CodeQL analysis, Docker image scanning, and other security checks.
5. **GitHub Integration**: PR management, branch cleanup, release automation.
6. **AWS Integration**: CloudFormation linting, CodeBuild integration, resource deployment.
