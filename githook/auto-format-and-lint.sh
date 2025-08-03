#!/usr/bin/env bash

set -euox pipefail

MAX_DEPTH=7

PYTHON_LINE_LENGTH=88
RUFF_LINT_EXTEND_SELECT='F,E,W,C90,I,N,D,UP,S,B,A,COM,C4,PT,Q,SIM,ARG,ERA,PD,PLC,PLE,PLW,TRY,FLY,NPY,PERF,FURB,RUF'
RUFF_LINT_IGNORE='D100,D103,D203,D213,S101,B008,A002,A004,COM812,PLC2701,TRY003'
N_PYTHON_FILES=$(find . -maxdepth "${MAX_DEPTH}" -type f -name '*.py' | wc -l)
if [[ "${N_PYTHON_FILES}" -gt 0 ]]; then
  PACKAGE_DIRECTORY="$(find . -maxdepth "${MAX_DEPTH}" -type f -name 'pyproject.toml' -exec dirname {} \; | head -n 1)"
  if [[ -n "${PACKAGE_DIRECTORY}" ]] && [[ -f "${PACKAGE_DIRECTORY}/uv.lock" ]]; then
    uv run --directory "${PACKAGE_DIRECTORY}" ruff format .
    uv run --directory "${PACKAGE_DIRECTORY}" ruff check --fix .
    uv run --directory "${PACKAGE_DIRECTORY}" pyright .
  elif [[ -n "${PACKAGE_DIRECTORY}" ]] && [[ -f "${PACKAGE_DIRECTORY}/poetry.lock" ]]; then
    poetry -C "${PACKAGE_DIRECTORY}" run ruff format .
    poetry -C "${PACKAGE_DIRECTORY}" run ruff check --fix .
    poetry -C "${PACKAGE_DIRECTORY}" run pyright .
  elif [[ -n "${PACKAGE_DIRECTORY}" ]]; then
    ruff format .
    ruff check --fix .
    pyright .
  else
    ruff format --exclude=build --exclude=.venv "--line-length=${PYTHON_LINE_LENGTH}" .
    ruff check --fix --exclude=build --exclude=.venv "--line-length=${PYTHON_LINE_LENGTH}" --extend-select="${RUFF_LINT_EXTEND_SELECT}" --ignore="${RUFF_LINT_IGNORE}" .
    pyright --threads=0 .
  fi
fi

N_BASH_FILES=$(find . -maxdepth "${MAX_DEPTH}" -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' \) | grep -cv '/\.venv/' || :)
if [[ "${N_BASH_FILES}" -gt 0 ]]; then
  find . -maxdepth "${MAX_DEPTH}" -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' \) \
    | grep -v '/\.venv/' \
    | xargs -t shellcheck
fi

if [[ -d '.github/workflows' ]]; then
  find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 \
    | xargs -0 -t actionlint
  find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 \
    | xargs -0 -t yamllint -d '{"extends": "relaxed", "rules": {"line-length": "disable"}}'
fi

N_TERRAFORM_FILES=$(find . -maxdepth "${MAX_DEPTH}" -type f \( -name '*.tf' -o -name '*.hcl' \) | wc -l)
if [[ "${N_TERRAFORM_FILES}" -gt 0 ]]; then
  terraform fmt -recursive .
  terragrunt hcl format --diff --working-dir .
  tflint --recursive --chdir=.
fi

# N_DOCKER_FILES=$(find . -maxdepth "${MAX_DEPTH}" -type f -name 'Dockerfile' | wc -l)
# if [[ "${N_DOCKER_FILES}" -gt 0 ]] || [[ "${N_TERRAFORM_FILES}" -gt 0 ]]; then
#   trivy filesystem --scanners vuln,secret,misconfig --skip-dirs .venv --skip-dirs .terraform --skip-dirs .terragrunt-cache --skip-dirs .git .
# fi
