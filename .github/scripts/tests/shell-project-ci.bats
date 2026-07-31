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
  git -C "${destination}" config user.email test@example.com
  git -C "${destination}" config user.name "Test User"
  git -C "${destination}" add -A
  git -C "${destination}" commit -q -m fixture
}

extract_step() {
  local step_name="$1"
  local output_script="$2"

  yq -r ".jobs.ci.steps[] | select(.name == \"${step_name}\") | .run" "${WORKFLOW}" > "${output_script}"
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

@test "validation passes with a valid command, search-path, and bats-version" {
  project="${TEST_TEMP}/passing project"
  prepare_fixture passing "${project}"

  run_step "Validate inputs" "${project}" \
    'QA_COMMAND=./scripts/qa.sh' \
    SEARCH_PATH=. \
    BATS_VERSION=1.13.0
  [ "${status}" -eq 0 ]
}

@test "an empty command fails validation" {
  project="${TEST_TEMP}/empty-command"
  prepare_fixture passing "${project}"

  run_step "Validate inputs" "${project}" \
    'QA_COMMAND=' \
    SEARCH_PATH=. \
    BATS_VERSION=1.13.0

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"command must not be empty"* ]]
}

@test "an invalid search-path fails validation" {
  project="${TEST_TEMP}/invalid-search-path"
  prepare_fixture passing "${project}"

  run_step "Validate inputs" "${project}" \
    'QA_COMMAND=./scripts/qa.sh' \
    'SEARCH_PATH=../escape' \
    BATS_VERSION=1.13.0

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"search-path must be a relative path"* ]]
}

@test "a non-numeric bats-version fails validation" {
  project="${TEST_TEMP}/invalid-bats-version"
  prepare_fixture passing "${project}"

  run_step "Validate inputs" "${project}" \
    'QA_COMMAND=./scripts/qa.sh' \
    SEARCH_PATH=. \
    'BATS_VERSION=latest'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"bats-version must be a numeric release version"* ]]
}

@test "the caller-provided QA command runs successfully" {
  project="${TEST_TEMP}/passing project"
  prepare_fixture passing "${project}"

  run_step "Run the caller-provided QA command" "${project}" \
    "GITHUB_WORKSPACE=${project}" 'QA_COMMAND=echo qa-ok'

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"qa-ok"* ]]
}

@test "a failing caller-provided QA command fails the workflow script" {
  project="${TEST_TEMP}/passing project"
  prepare_fixture passing "${project}"

  run_step "Run the caller-provided QA command" "${project}" \
    "GITHUB_WORKSPACE=${project}" 'QA_COMMAND=exit 1'

  [ "${status}" -ne 0 ]
}

@test "a multi-line caller-provided QA command aborts on the first failing line" {
  project="${TEST_TEMP}/passing project"
  prepare_fixture passing "${project}"

  run_step "Run the caller-provided QA command" "${project}" \
    "GITHUB_WORKSPACE=${project}" $'QA_COMMAND=false\ntrue'

  [ "${status}" -ne 0 ]
}

@test "the caller-provided QA command runs in the configured working directory" {
  project="${TEST_TEMP}/passing project"
  prepare_fixture passing "${project}"

  run_step "Run the caller-provided QA command" "${project}" \
    "GITHUB_WORKSPACE=${project}" 'QA_COMMAND=cat marker-file'

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"marker"* ]]
}

@test "the workflow fails when the QA command rewrites a tracked file" {
  project="${TEST_TEMP}/passing project"
  prepare_fixture passing "${project}"

  run_step "Run the caller-provided QA command" "${project}" \
    "GITHUB_WORKSPACE=${project}" 'QA_COMMAND=echo rewritten > marker-file'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"modified tracked files"* ]]
}

@test "the workflow fails when the QA command rewrites a tracked file outside search-path" {
  project="${TEST_TEMP}/passing project"
  prepare_fixture passing "${project}"
  mkdir -p "${project}/sub"

  run_step "Run the caller-provided QA command" "${project}/sub" \
    "GITHUB_WORKSPACE=${project}" 'QA_COMMAND=echo rewritten > ../marker-file'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"modified tracked files"* ]]
}

@test "the workflow fails when the QA command stages a rewrite without leaving it unstaged" {
  project="${TEST_TEMP}/passing project"
  prepare_fixture passing "${project}"

  run_step "Run the caller-provided QA command" "${project}" \
    "GITHUB_WORKSPACE=${project}" 'QA_COMMAND=echo rewritten > marker-file && git add marker-file'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"modified tracked files"* ]]
}
