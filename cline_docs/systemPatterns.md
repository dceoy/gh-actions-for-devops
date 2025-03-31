# System Patterns

## Architecture Overview

The `gh-actions-for-devops` project follows a modular architecture where each workflow is designed as a reusable component that can be called from other workflows. This enables composition of complex CI/CD pipelines from simpler building blocks.

## Key Technical Decisions

1. **Reusable Workflows**: Using GitHub's `workflow_call` trigger to create reusable workflow components.
2. **Parameterization**: Extensive use of input parameters and secrets to make workflows flexible and configurable.
3. **Composition Over Inheritance**: Complex workflows (like CI) are built by composing multiple specialized workflows.
4. **Explicit Versioning**: Action versions are pinned using SHA hashes to prevent unexpected changes.
5. **Automated Documentation**: README.md is automatically generated from workflow files.
6. **Security First**: Security scanning is integrated into build and deployment processes.

## Design Patterns

### Workflow Structure Pattern

Each reusable workflow follows a consistent structure:
1. **Metadata**: Name and description
2. **Triggers**: Primarily `workflow_call` with defined inputs and secrets
3. **Permissions**: Explicitly defined permissions following principle of least privilege
4. **Defaults**: Shell configuration and working directory
5. **Jobs**: The actual work to be performed

### Input Parameter Pattern

Workflows use a consistent pattern for input parameters:
1. **Required vs Optional**: Clear indication of which parameters are required
2. **Default Values**: Sensible defaults for optional parameters
3. **Descriptions**: Detailed descriptions for all parameters
4. **Type Checking**: Explicit type definitions (string, boolean, number)

### Conditional Execution Pattern

Jobs and steps use conditional execution based on:
1. **Event Types**: Different behavior for push, pull_request, workflow_dispatch
2. **Input Parameters**: Enabling/disabling features based on inputs
3. **Previous Job Results**: Using job needs and if conditions

### Error Handling Pattern

Workflows handle errors through:
1. **Exit Codes**: Configurable exit codes for different tools
2. **Failure Thresholds**: Configurable severity thresholds for linting and scanning
3. **Continue-on-Error**: Strategic use of continue-on-error for non-critical steps

## File Organization

```
.
├── .github/workflows/  # GitHub Actions workflow files
├── githook/           # Git hook scripts for local development
├── src/               # Source code for supporting tools
│   ├── build_readme_md.py  # Script to generate README.md
│   └── ...
└── workflows/         # Reusable workflow files (main content)
    ├── docker-*.yml   # Docker-related workflows
    ├── terraform-*.yml  # Terraform-related workflows
    └── ...
```

## Integration Points

1. **GitHub Actions**: Primary integration point as the execution environment
2. **Docker Registries**: For pushing and pulling container images
3. **AWS Services**: For deployment and infrastructure management
4. **PyPI**: For Python package publishing
5. **Security Scanning Tools**: Trivy, Hadolint, CodeQL, etc.
