gh-actions-for-devops
=====================

GitHub Actions workflows for DevOps

[![CI](https://github.com/dceoy/gh-actions-for-devops/actions/workflows/ci.yml/badge.svg)](https://github.com/dceoy/gh-actions-for-devops/actions/workflows/ci.yml)

Reusable workflows
------------------

- [.github/workflows/](.github/workflows/)

  - [aws-cloudformation-lint.yml](.github/workflows/aws-cloudformation-lint.yml)
    - Lint for AWS CloudFormation

  - [aws-codebuild-run.yml](.github/workflows/aws-codebuild-run.yml)
    - Build using an AWS CodeBuild project

  - [claude-code-action.yml](.github/workflows/claude-code-action.yml)
    - Claude Code action

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

  - [github-actions-lint.yml](.github/workflows/github-actions-lint.yml)
    - Lint for GitHub Actions workflows

  - [github-codeql-analysis.yml](.github/workflows/github-codeql-analysis.yml)
    - GitHub CodeQL Analysis

  - [github-merged-branch-deletion.yml](.github/workflows/github-merged-branch-deletion.yml)
    - Deletion of merged branches on GitHub

  - [github-pr-branch-aggregation.yml](.github/workflows/github-pr-branch-aggregation.yml)
    - Aggregation of open pull request branches

  - [github-release.yml](.github/workflows/github-release.yml)
    - Release on GitHub

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

  - [python-package-release-on-pypi-and-github.yml](.github/workflows/python-package-release-on-pypi-and-github.yml)
    - Python package release on PyPI and GitHub

  - [python-pyinstaller.yml](.github/workflows/python-pyinstaller.yml)
    - Build using PyInstaller

  - [r-package-format-and-pr.yml](.github/workflows/r-package-format-and-pr.yml)
    - Formatting for R

  - [r-package-lint.yml](.github/workflows/r-package-lint.yml)
    - Lint for R

  - [shell-lint.yml](.github/workflows/shell-lint.yml)
    - Lint for Shell

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

  - [typescript-lint-and-scan.yml](.github/workflows/typescript-lint-and-scan.yml)
    - Lint and security scan for TypeScript

  - [web-api-monitoring-with-slack.yml](.github/workflows/web-api-monitoring-with-slack.yml)
    - Synthetic web API monitoring with Slack notification

  - [yaml-lint.yml](.github/workflows/yaml-lint.yml)
    - Lint for YAML
