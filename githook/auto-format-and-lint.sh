#!/usr/bin/env bash

set -euox pipefail

PYTHON_LINE_LENGTH=88
RUFF_LINT_EXTEND_SELECT='F,E,W,C90,I,N,D,UP,S,B,A,COM,C4,PT,Q,SIM,ARG,ERA,PD,PLC,PLE,PLW,TRY,FLY,NPY,PERF,FURB,RUF'
RUFF_LINT_IGNORE='D100,D103,D203,D213,S101,B008,A002,A004,COM812,PLC2701,TRY003'

COMMON_EXCLUDE_PATHS=(
  ':(exclude,glob)**/.*/**'
  ':(exclude,glob)**/.*'
  ':(exclude,glob)**/.venv/**'
  ':(exclude,glob)**/node_modules/**'
  ':(exclude,glob)**/htmlcov/**'
  ':(exclude,glob)**/coverage/**'
)
TS_EXCLUDE_PATHS=("${COMMON_EXCLUDE_PATHS[@]}" ':(exclude,glob)**/site/**')

N_PYTHON_FILES=$(git ls-files -- '*.py' "${COMMON_EXCLUDE_PATHS[@]}" | wc -l)
if [[ "${N_PYTHON_FILES}" -gt 0 ]]; then
  PYPROJECT_FILE="$(git ls-files -- 'pyproject.toml' '*/pyproject.toml' "${COMMON_EXCLUDE_PATHS[@]}" | head -n 1)"
  PACKAGE_DIRECTORY=''
  if [[ -n "${PYPROJECT_FILE}" ]]; then
    PACKAGE_DIRECTORY="$(dirname "${PYPROJECT_FILE}")"
  fi
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

N_BASH_FILES=$(git ls-files -- '*.sh' '*.bash' '*.bats' "${COMMON_EXCLUDE_PATHS[@]}" | wc -l)
if [[ "${N_BASH_FILES}" -gt 0 ]]; then
  git ls-files -z -- '*.sh' '*.bash' '*.bats' "${COMMON_EXCLUDE_PATHS[@]}" \
    | xargs -0 -t shellcheck
fi

N_TYPESCRIPT_FILES=$(git ls-files -- '*.ts' '*.tsx' "${TS_EXCLUDE_PATHS[@]}" | wc -l)
N_JAVASCRIPT_FILES=$(git ls-files -- '*.js' '*.jsx' "${TS_EXCLUDE_PATHS[@]}" | wc -l)
if [[ "${N_TYPESCRIPT_FILES}" -gt 0 ]] || [[ "${N_JAVASCRIPT_FILES}" -gt 0 ]]; then
  PACKAGE_JSON_FILE=$(git ls-files -- 'package.json' '*/package.json' "${COMMON_EXCLUDE_PATHS[@]}" | head -n 1)
  if [[ -n "${PACKAGE_JSON_FILE}" ]]; then
    PACKAGE_DIRECTORY="$(dirname "${PACKAGE_JSON_FILE}")"
    NODE_MODULES_BIN="${PACKAGE_DIRECTORY}/node_modules/.bin"
    TSCONFIG_JSON_FILE="${PACKAGE_DIRECTORY}/tsconfig.json"
    PATH="${NODE_MODULES_BIN}:${PATH}"
    prettier --write "${PACKAGE_DIRECTORY}/**/*.{js,jsx,ts,tsx,json,css,scss}"
    eslint --fix --ext .js,.jsx,.ts,.tsx --no-error-on-unmatched-pattern "${PACKAGE_DIRECTORY}"
  else
    PACKAGE_DIRECTORY='.'
    prettier --write '**/*.{js,jsx,ts,tsx,json,css,scss}'
    eslint --fix --ext .js,.jsx,.ts,.tsx --no-error-on-unmatched-pattern .
  fi
  if [[ "${N_TYPESCRIPT_FILES}" -gt 0 ]]; then
    TSCONFIG_JSON_FILE="${PACKAGE_DIRECTORY}/tsconfig.json"
    if [[ -f "${TSCONFIG_JSON_FILE}" ]]; then
      tsc --noEmit --project "${TSCONFIG_JSON_FILE}"
    else
      tsc --noEmit
    fi
  fi
fi

N_HTML_FILES=$(git ls-files -- '*.html' '*.htm' "${COMMON_EXCLUDE_PATHS[@]}" | wc -l)
if [[ "${N_HTML_FILES}" -gt 0 ]]; then
  prettier --write './**/*.{html,htm}'
fi

N_MARKDOWN_FILES=$(git ls-files -- '*.md' "${COMMON_EXCLUDE_PATHS[@]}" | wc -l)
if [[ "${N_MARKDOWN_FILES}" -gt 0 ]]; then
  prettier --write './**/*.md'
  # markdownlint-cli2 './**/*.md'
fi

N_GO_FILES=$(git ls-files -- '*.go' "${COMMON_EXCLUDE_PATHS[@]}" | wc -l)
if [[ "${N_GO_FILES}" -gt 0 ]]; then
  golangci-lint fmt --enable=gofumpt --enable=goimports
  golangci-lint run --fix
fi

if [[ -d '.github/workflows' ]]; then
  zizmor --fix=safe .github/workflows
  WORKFLOW_EXCLUDE_PATHS=(
    ':(exclude,glob).github/workflows/**/.*/**'
    ':(exclude,glob).github/workflows/**/.*'
  )
  N_WORKFLOW_YAML_FILES=$(git ls-files -- '.github/workflows/**.yml' '.github/workflows/**.yaml' "${WORKFLOW_EXCLUDE_PATHS[@]}" | wc -l)
  if [[ "${N_WORKFLOW_YAML_FILES}" -gt 0 ]]; then
    git ls-files -z -- '.github/workflows/**.yml' '.github/workflows/**.yaml' "${WORKFLOW_EXCLUDE_PATHS[@]}" \
      | xargs -0 -t actionlint
    git ls-files -z -- '.github/workflows/**.yml' '.github/workflows/**.yaml' "${WORKFLOW_EXCLUDE_PATHS[@]}" \
      | xargs -0 -t yamllint -d '{"extends": "relaxed", "rules": {"line-length": "disable"}}'
  fi
fi

N_TERRAFORM_FILES=$(git ls-files -- '*.tf' '*.hcl' "${COMMON_EXCLUDE_PATHS[@]}" | wc -l)
if [[ "${N_TERRAFORM_FILES}" -gt 0 ]]; then
  terraform fmt -recursive .
  terragrunt hcl format --diff --working-dir .
  tflint --recursive --chdir=.
fi

N_DOCKER_FILES=$(git ls-files -- 'Dockerfile' '*/Dockerfile' "${COMMON_EXCLUDE_PATHS[@]}" | wc -l)
# if [[ "${N_DOCKER_FILES}" -gt 0 ]] || [[ "${N_TERRAFORM_FILES}" -gt 0 ]]; then
#   trivy filesystem --scanners vuln,secret,misconfig --skip-dirs .venv --skip-dirs .terraform --skip-dirs .terragrunt-cache --skip-dirs .git .
# fi

if [[ -d '.github/workflows' ]] || [[ "${N_TERRAFORM_FILES}" -gt 0 ]] || [[ "${N_DOCKER_FILES}" -gt 0 ]]; then
  checkov --framework=all --output=github_failed_only --directory=.
fi
