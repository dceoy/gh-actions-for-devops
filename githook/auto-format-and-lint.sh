#!/usr/bin/env bash

set -euox pipefail

MAX_DEPTH=7

PYTHON_LINE_LENGTH=88
RUFF_LINT_EXTEND_SELECT='F,E,W,C90,I,N,D,UP,S,B,A,COM,C4,PT,Q,SIM,ARG,ERA,PD,PLC,PLE,PLW,TRY,FLY,NPY,PERF,FURB,RUF'
RUFF_LINT_IGNORE='D100,D103,D203,D213,S101,B008,A002,A004,COM812,PLC2701,TRY003'
N_PYTHON_FILES=$(find . -maxdepth "${MAX_DEPTH}" -path '*/.*' -prune -o -type f -name '*.py' -print | wc -l)
if [[ "${N_PYTHON_FILES}" -gt 0 ]]; then
  PACKAGE_DIRECTORY="$(find . -maxdepth "${MAX_DEPTH}" -path '*/.*' -prune -o -type f -name 'pyproject.toml' -exec dirname {} \; | head -n 1)"
  if [[ -n "${PACKAGE_DIRECTORY}" ]] && [[ -f "${PACKAGE_DIRECTORY}/uv.lock" ]]; then
    uv run --directory "${PACKAGE_DIRECTORY}" ruff format .
    uv run --directory "${PACKAGE_DIRECTORY}" ruff check --fix .
    uv run --directory "${PACKAGE_DIRECTORY}" pyright .
  elif [[ -n "${PACKAGE_DIRECTORY}" ]] && [[ -f "${PACKAGE_DIRECTORY}/poetry.lock" ]]; then
    poetry -C "${PACKAGE_DIRECTORY}" run ruff format .
    poetry -C "${PACKAGE_DIRECTORY}" run ruff check --fix .
    poetry -C "${PACKAGE_DIRECTORY}" run pyright .
  elif [[ -n "${PACKAGE_DIRECTORY}" ]]; then
    ruff format "${PACKAGE_DIRECTORY}"
    ruff check --fix "${PACKAGE_DIRECTORY}"
    pyright "${PACKAGE_DIRECTORY}"
  else
    ruff format --exclude=build --exclude=.venv "--line-length=${PYTHON_LINE_LENGTH}" .
    ruff check --fix --exclude=build --exclude=.venv "--line-length=${PYTHON_LINE_LENGTH}" --extend-select="${RUFF_LINT_EXTEND_SELECT}" --ignore="${RUFF_LINT_IGNORE}" .
    pyright --threads=0 .
  fi
fi

N_BASH_FILES=$(find . -maxdepth "${MAX_DEPTH}" -path '*/.*' -prune -o -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' \) -print | wc -l)
if [[ "${N_BASH_FILES}" -gt 0 ]]; then
  find . -maxdepth "${MAX_DEPTH}" -path '*/.*' -prune -o -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' \) -print0 \
    | xargs -0 -t shellcheck
fi

N_TYPESCRIPT_FILES=$(find . -maxdepth "${MAX_DEPTH}" \( -path '*/.*' -o -path '*/node_modules/*' -o -path '*/htmlcov/*' -o -path '*/coverage/*' -o -path '*/site/*' \) -prune -o -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) -print | wc -l)
if [[ "${N_TYPESCRIPT_FILES}" -gt 0 ]]; then
  PACKAGE_JSON_FILE=$(find . -maxdepth "${MAX_DEPTH}" \( -path '*/.*' -o -path '*/node_modules/*' -o -path '*/htmlcov/*' -o -path '*/coverage/*' \) -prune -o -type f -name 'package.json' -print -quit)
  if [[ -n "${PACKAGE_JSON_FILE}" ]]; then
    PACKAGE_DIRECTORY="$(dirname "${PACKAGE_JSON_FILE}")"
    NODE_MODULES_BIN="${PACKAGE_DIRECTORY}/node_modules/.bin"
    PATH="${NODE_MODULES_BIN}:${PATH}"
    eslint --ext .js,.jsx,.ts,.tsx "${PACKAGE_DIRECTORY}"
    prettier --check "${PACKAGE_DIRECTORY}/**/*.{js,jsx,ts,tsx,json,css,scss}"
    tsc --noEmit --project "${PACKAGE_DIRECTORY}/tsconfig.json"
  else
    eslint --ext .js,.jsx,.ts,.tsx .
    prettier --check '**/*.{js,jsx,ts,tsx,json,css,scss}'
    tsc --noEmit
  fi
fi

N_HTML_FILES=$(find . -maxdepth "${MAX_DEPTH}" \( -path '*/.*' -o -path '*/htmlcov/*' -o -path '*/coverage/*' \) -prune -o -type f \( -name '*.html' -o -name '*.htm' \) -print | wc -l)
if [[ "${N_HTML_FILES}" -gt 0 ]]; then
  prettier --check './**/*.{html,htm}'
fi

N_MARKDOWN_FILES=$(find . -maxdepth "${MAX_DEPTH}" -path '*/.*' -prune -o -type f -name '*.md' -print | wc -l)
if [[ "${N_MARKDOWN_FILES}" -gt 0 ]]; then
  prettier --check './**/*.md'
  # markdownlint-cli2 './**/*.md'
fi

N_GO_FILES=$(find . -maxdepth "${MAX_DEPTH}" -path '*/.*' -prune -o -type f -name '*.go' -print | wc -l)
if [[ "${N_GO_FILES}" -gt 0 ]]; then
  golangci-lint fmt --enable=gofumpt --enable=goimports
  golangci-lint run --fix
fi

if [[ -d '.github/workflows' ]]; then
  zizmor --fix=safe .github/workflows
  find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 \
    | xargs -0 -t actionlint
  find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 \
    | xargs -0 -t yamllint -d '{"extends": "relaxed", "rules": {"line-length": "disable"}}'
fi

N_TERRAFORM_FILES=$(find . -maxdepth "${MAX_DEPTH}" -path '*/.*' -prune -o -type f \( -name '*.tf' -o -name '*.hcl' \) -print | wc -l)
if [[ "${N_TERRAFORM_FILES}" -gt 0 ]]; then
  terraform fmt -recursive .
  terragrunt hcl format --diff --working-dir .
  tflint --recursive --chdir=.
fi

# N_DOCKER_FILES=$(find . -maxdepth "${MAX_DEPTH}" -path '*/.*' -prune -o -type f -name 'Dockerfile' -print | wc -l)
# if [[ "${N_DOCKER_FILES}" -gt 0 ]] || [[ "${N_TERRAFORM_FILES}" -gt 0 ]]; then
#   trivy filesystem --scanners vuln,secret,misconfig --skip-dirs .venv --skip-dirs .terraform --skip-dirs .terragrunt-cache --skip-dirs .git .
# fi
