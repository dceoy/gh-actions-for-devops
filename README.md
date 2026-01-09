# gh-actions-for-devops

A comprehensive collection of reusable GitHub Actions workflows for DevOps automation, covering Docker operations, AWS deployments, security scanning, code quality checks, and more.

[![CI](https://github.com/dceoy/gh-actions-for-devops/actions/workflows/ci.yml/badge.svg)](https://github.com/dceoy/gh-actions-for-devops/actions/workflows/ci.yml)

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Reusable Workflows](#reusable-workflows)
- [License](#license)

## Overview

This repository provides production-ready, reusable GitHub Actions workflows that can be called from other repositories to standardize and simplify your CI/CD pipelines. These workflows are designed to be modular, secure, and easy to integrate into your existing projects.

### Key Features

- **Docker Operations**: Build, scan, push, and deploy Docker images
- **AWS Integration**: Deploy to AWS using Terraform, CodeBuild, CloudFormation, and more
- **Security Scanning**: Automated security checks for dependencies, containers, and infrastructure
- **Code Quality**: Linting and formatting for multiple languages and file types
- **Automation**: Dependabot auto-merge, PR management, and release automation

## Prerequisites

To use these reusable workflows, you'll need:

- GitHub repository with Actions enabled
- Appropriate secrets configured in your repository (e.g., `AWS_ACCESS_KEY_ID`, `DOCKER_HUB_TOKEN`)
- Required permissions for the specific workflow you're using

## Usage

To use a reusable workflow in your repository, create a workflow file (e.g., `.github/workflows/my-workflow.yml`) and reference the desired workflow:

```yaml
name: My Workflow
on:
  push:
    branches: [main]

jobs:
  docker-build-and-push:
    uses: dceoy/gh-actions-for-devops/.github/workflows/docker-build-and-push.yml@main
    with:
      registry: docker.io
      registry-user: myusername
      image-name: my-app
      context: .
    secrets:
      DOCKER_TOKEN: ${{ secrets.DOCKER_TOKEN }}
```

## Reusable Workflows

The workflows are organized by category for easier navigation. Each workflow is designed to be called from other repositories using the `workflow_call` trigger.

### All Reusable Workflows

- [aws-cloudformation-lint.yml](.github/workflows/aws-cloudformation-lint.yml)
  - Lint for AWS CloudFormation

- [aws-codebuild-run.yml](.github/workflows/aws-codebuild-run.yml)
  - Build using an AWS CodeBuild project

- [aws-parameter-store-update.yml](.github/workflows/aws-parameter-store-update.yml)
  - Update AWS Parameter Store values

- [claude-code-action.yml](.github/workflows/claude-code-action.yml)
  - Claude Code Action

- [claude-code-bot.yml](.github/workflows/claude-code-bot.yml)
  - Mention bot using Claude Code

- [claude-code-review.yml](.github/workflows/claude-code-review.yml)
  - Pull request review using Claude Code

- [dependabot-auto-merge.yml](.github/workflows/dependabot-auto-merge.yml)
  - Dependabot auto-merge

- [docker-build-and-push.yml](.github/workflows/docker-build-and-push.yml)
  - Docker image build and push

- [docker-build-with-multi-targets.yml](.github/workflows/docker-build-with-multi-targets.yml)
  - Docker image build and save for multiple build targets

- [docker-buildx-bake.yml](.github/workflows/docker-buildx-bake.yml)
  - Docker image build from a bake definition file

- [docker-image-scan.yml](.github/workflows/docker-image-scan.yml)
  - Security scan for Docker images

- [docker-lint-and-scan.yml](.github/workflows/docker-lint-and-scan.yml)
  - Lint and security scan for Dockerfile

- [docker-pull-from-aws.yml](.github/workflows/docker-pull-from-aws.yml)
  - Docker image pull from AWS

- [docker-save-and-terraform-deploy-to-aws.yml](.github/workflows/docker-save-and-terraform-deploy-to-aws.yml)
  - Docker image save and resource deployment to AWS using Terraform

- [gcloud-infra-manager-deployments.yml](.github/workflows/gcloud-infra-manager-deployments.yml)
  - Deployment of Google Cloud resources using Infrastructure Manager

- [gemini-cli-to-slack.yml](.github/workflows/gemini-cli-to-slack.yml)
  - Gemini CLI with Slack notification

- [github-actions-lint-and-scan.yml](.github/workflows/github-actions-lint-and-scan.yml)
  - Lint and security scan for GitHub Actions workflows

- [github-codeql-analysis.yml](.github/workflows/github-codeql-analysis.yml)
  - GitHub CodeQL Analysis

- [github-merged-branch-deletion.yml](.github/workflows/github-merged-branch-deletion.yml)
  - Deletion of merged branches on GitHub

- [github-pr-branch-aggregation.yml](.github/workflows/github-pr-branch-aggregation.yml)
  - Aggregation of open pull request branches

- [github-release.yml](.github/workflows/github-release.yml)
  - Release on GitHub

- [go-package-lint-and-scan.yml](.github/workflows/go-package-lint-and-scan.yml)
  - Lint and security scan for Go

- [html-lint-and-scan.yml](.github/workflows/html-lint-and-scan.yml)
  - Lint and scan for HTML/CSS

- [json-lint.yml](.github/workflows/json-lint.yml)
  - Lint for JSON

- [json-schema-validation.yml](.github/workflows/json-schema-validation.yml)
  - Schema validation for JSON

- [microsoft-defender-for-devops.yml](.github/workflows/microsoft-defender-for-devops.yml)
  - Microsoft Defender for Devops

- [pr-agent.yml](.github/workflows/pr-agent.yml)
  - PR-agent

- [python-package-format-and-pr.yml](.github/workflows/python-package-format-and-pr.yml)
  - Formatting for Python

- [python-package-lint-and-scan.yml](.github/workflows/python-package-lint-and-scan.yml)
  - Lint and security scan for Python

- [python-package-mkdocs-gh-deploy.yml](.github/workflows/python-package-mkdocs-gh-deploy.yml)
  - Build and deployment of MkDocs documentation

- [python-package-release-on-pypi-and-github.yml](.github/workflows/python-package-release-on-pypi-and-github.yml)
  - Python package release on PyPI and GitHub

- [python-package-test.yml](.github/workflows/python-package-test.yml)
  - Test for Python Package

- [python-pyinstaller.yml](.github/workflows/python-pyinstaller.yml)
  - Build using PyInstaller

- [r-package-format-and-pr.yml](.github/workflows/r-package-format-and-pr.yml)
  - Formatting for R

- [r-package-lint.yml](.github/workflows/r-package-lint.yml)
  - Lint for R

- [shell-lint.yml](.github/workflows/shell-lint.yml)
  - Lint for Shell

- [speckit-init.yml](.github/workflows/speckit-init.yml)
  - Spec Kit initialization

- [terraform-deploy-to-aws.yml](.github/workflows/terraform-deploy-to-aws.yml)
  - Deployment of AWS resources using Terraform

- [terraform-format-and-pr.yml](.github/workflows/terraform-format-and-pr.yml)
  - Formatting for Terraform

- [terraform-lint-and-scan.yml](.github/workflows/terraform-lint-and-scan.yml)
  - Lint and security scan for Terraform

- [terraform-lock-files-upgrade-and-pr-merge.yml](.github/workflows/terraform-lock-files-upgrade-and-pr-merge.yml)
  - Upgrade of Terraform lock files and pull request merge

- [terraform-lock-files-upgrade.yml](.github/workflows/terraform-lock-files-upgrade.yml)
  - Upgrade of Terraform lock files

- [terragrunt-aws-switch-resources.yml](.github/workflows/terragrunt-aws-switch-resources.yml)
  - Switcher to apply or destroy AWS resources using Terragrunt

- [toml-lint.yml](.github/workflows/toml-lint.yml)
  - Lint for TOML

- [typescript-package-format-and-pr.yml](.github/workflows/typescript-package-format-and-pr.yml)
  - Formatting for TypeScript

- [typescript-package-lint-and-scan.yml](.github/workflows/typescript-package-lint-and-scan.yml)
  - Lint and security scan for TypeScript

- [web-api-monitoring-with-slack.yml](.github/workflows/web-api-monitoring-with-slack.yml)
  - Synthetic web API monitoring with Slack notification

- [yaml-lint.yml](.github/workflows/yaml-lint.yml)
  - Lint for YAML

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2024 Daichi Narushima
