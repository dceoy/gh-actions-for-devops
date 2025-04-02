#!/usr/bin/env bash

set -euox pipefail

terraform fmt -recursive . && terragrunt hclfmt --diff --working-dir .
tflint --recursive --chdir=.
trivy filesystem --scanners vuln,secret,misconfig .
