#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/shell-project-ci.yml"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures/shell-project-ci"
  TEST_TEMP="$(mktemp -d)"
}

teardown() {
  rm -rf "${TEST_TEMP}"
}

prepare_fixture() {
  local fixture_name="$1"
  local destination="$2"

  mkdir -p "${destination}"
  while IFS= read -r -d '' fixture; do
    relative_path="${fixture#"${FIXTURES}/${fixture_name}/"}"
    output_path="${destination}/${relative_path%.fixture}"
    mkdir -p "$(dirname "${output_path}")"
    cp "${fixture}" "${output_path}"
  done < <(find "${FIXTURES}/${fixture_name}" -type f -name '*.fixture' -print0)
  git -C "${destination}" init -q
  git -C "${destination}" add .
}

extract_step() {
  local step_name="$1"
  local output_script="$2"

  yq -r ".jobs.test.steps[] | select(.name == \"${step_name}\") | .run" "${WORKFLOW}" > "${output_script}"
}

run_step() {
  local step_name="$1"
  local working_directory="$2"
  shift 2
  local step_script="${TEST_TEMP}/${step_name// /-}.sh"

  extract_step "${step_name}" "${step_script}"
  # shellcheck disable=SC2016
  run env "$@" bash -c 'cd "$1" && exec bash -euo pipefail "$2"' _ "${working_directory}" "${step_script}"
}

@test "all checks pass with tracked paths containing spaces" {
  project="${TEST_TEMP}/passing project"
  prepare_fixture passing "${project}"

  run_step "Run ShellCheck" "${project}" $'FILE_NAMES=lib/*.sh\ntest/*.bats'
  [ "${status}" -eq 0 ]

  run_step "Check formatting with shfmt" "${project}" \
    $'FILE_NAMES=lib/*.sh\ntest/*.bats' \
    SHFMT_INDENT=2 \
    SHFMT_BINARY_NEXT_LINE=true \
    SHFMT_CASE_INDENT=true \
    SHFMT_SPACE_REDIRECTS=true
  [ "${status}" -eq 0 ]

  run_step "Run Bats tests" "${project}" 'TEST_PATHS=test/*.bats'
  [ "${status}" -eq 0 ]
}

@test "a ShellCheck violation fails the workflow script" {
  project="${TEST_TEMP}/lint-failure"
  prepare_fixture lint-failure "${project}"

  run_step "Run ShellCheck" "${project}" 'FILE_NAMES=*.sh'

  [ "${status}" -ne 0 ]
}

@test "a shfmt violation fails the workflow script" {
  project="${TEST_TEMP}/format-failure"
  prepare_fixture format-failure "${project}"

  run_step "Check formatting with shfmt" "${project}" \
    'FILE_NAMES=*.sh' \
    SHFMT_INDENT=2 \
    SHFMT_BINARY_NEXT_LINE=true \
    SHFMT_CASE_INDENT=true \
    SHFMT_SPACE_REDIRECTS=true

  [ "${status}" -ne 0 ]
}

@test "a failed Bats test fails the workflow script" {
  project="${TEST_TEMP}/bats-failure"
  prepare_fixture bats-failure "${project}"

  run_step "Run Bats tests" "${project}" 'TEST_PATHS=test/*.bats'

  [ "${status}" -ne 0 ]
}

@test "an empty tracked-file selection fails explicitly" {
  project="${TEST_TEMP}/empty-selection"
  prepare_fixture passing "${project}"

  run_step "Run ShellCheck" "${project}" 'FILE_NAMES=missing/*.sh'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"selected no tracked files"* ]]
}
