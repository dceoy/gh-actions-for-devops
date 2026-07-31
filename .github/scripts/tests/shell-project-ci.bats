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

install_fake_tool() {
  local home_dir="$1"
  local tool_name="$2"
  local version_output="$3"

  mkdir -p "${home_dir}/.local/bin"
  cat > "${home_dir}/.local/bin/${tool_name}" << STUB
#!/usr/bin/env bash
printf '%s\n' "${version_output}"
STUB
  chmod +x "${home_dir}/.local/bin/${tool_name}"
}

stub_curl() {
  local stub_dir="$1"
  local log_file="$2"

  mkdir -p "${stub_dir}"
  cat > "${stub_dir}/curl" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${log_file}"
exit 1
STUB
  chmod +x "${stub_dir}/curl"
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

@test "the ShellCheck install step skips reinstalling when the cached version matches the pin" {
  fake_home="${TEST_TEMP}/fake-home"
  install_fake_tool "${fake_home}" shellcheck "version: 0.10.0"
  stub_curl "${TEST_TEMP}/stub-bin" "${TEST_TEMP}/curl-invocations.log"

  run_step "Install ShellCheck if the pinned version is missing" "${TEST_TEMP}" \
    "HOME=${fake_home}" \
    "PATH=${TEST_TEMP}/stub-bin:${PATH}" \
    "GITHUB_PATH=${TEST_TEMP}/github-path" \
    RUNNER_OS=Linux \
    RUNNER_ARCH=X64 \
    "RUNNER_TEMP=${TEST_TEMP}/runner-temp" \
    SHELLCHECK_VERSION=v0.10.0

  [ "${status}" -eq 0 ]
  [ ! -s "${TEST_TEMP}/curl-invocations.log" ]
}

@test "the ShellCheck install step reinstalls when the cached version does not match the pin" {
  fake_home="${TEST_TEMP}/fake-home"
  install_fake_tool "${fake_home}" shellcheck "version: 0.9.0"
  stub_curl "${TEST_TEMP}/stub-bin" "${TEST_TEMP}/curl-invocations.log"

  run_step "Install ShellCheck if the pinned version is missing" "${TEST_TEMP}" \
    "HOME=${fake_home}" \
    "PATH=${TEST_TEMP}/stub-bin:${PATH}" \
    "GITHUB_PATH=${TEST_TEMP}/github-path" \
    RUNNER_OS=Linux \
    RUNNER_ARCH=X64 \
    "RUNNER_TEMP=${TEST_TEMP}/runner-temp" \
    SHELLCHECK_VERSION=v0.10.0

  grep -q "shellcheck-v0.10.0.linux.x86_64.tar.xz" "${TEST_TEMP}/curl-invocations.log"
}

@test "the shfmt install step skips reinstalling when the cached version matches the pin" {
  fake_home="${TEST_TEMP}/fake-home"
  install_fake_tool "${fake_home}" shfmt "v3.10.0"
  stub_curl "${TEST_TEMP}/stub-bin" "${TEST_TEMP}/curl-invocations.log"

  run_step "Install shfmt if the pinned version is missing" "${TEST_TEMP}" \
    "HOME=${fake_home}" \
    "PATH=${TEST_TEMP}/stub-bin:${PATH}" \
    "GITHUB_PATH=${TEST_TEMP}/github-path" \
    RUNNER_OS=Linux \
    RUNNER_ARCH=X64 \
    "RUNNER_TEMP=${TEST_TEMP}/runner-temp" \
    SHFMT_VERSION=v3.10.0

  [ "${status}" -eq 0 ]
  [ ! -s "${TEST_TEMP}/curl-invocations.log" ]
}

@test "the shfmt install step reinstalls when the cached version does not match the pin" {
  fake_home="${TEST_TEMP}/fake-home"
  install_fake_tool "${fake_home}" shfmt "v3.9.0"
  stub_curl "${TEST_TEMP}/stub-bin" "${TEST_TEMP}/curl-invocations.log"

  run_step "Install shfmt if the pinned version is missing" "${TEST_TEMP}" \
    "HOME=${fake_home}" \
    "PATH=${TEST_TEMP}/stub-bin:${PATH}" \
    "GITHUB_PATH=${TEST_TEMP}/github-path" \
    RUNNER_OS=Linux \
    RUNNER_ARCH=X64 \
    "RUNNER_TEMP=${TEST_TEMP}/runner-temp" \
    SHFMT_VERSION=v3.10.0

  grep -q "shfmt_v3.10.0_linux_amd64" "${TEST_TEMP}/curl-invocations.log"
}

@test "the actionlint install step skips reinstalling when the cached version matches the pin" {
  fake_home="${TEST_TEMP}/fake-home"
  install_fake_tool "${fake_home}" actionlint "1.7.7"
  stub_curl "${TEST_TEMP}/stub-bin" "${TEST_TEMP}/curl-invocations.log"

  run_step "Install actionlint if the pinned version is missing" "${TEST_TEMP}" \
    "HOME=${fake_home}" \
    "PATH=${TEST_TEMP}/stub-bin:${PATH}" \
    "GITHUB_PATH=${TEST_TEMP}/github-path" \
    RUNNER_OS=Linux \
    RUNNER_ARCH=X64 \
    "RUNNER_TEMP=${TEST_TEMP}/runner-temp" \
    ACTIONLINT_VERSION=v1.7.7

  [ "${status}" -eq 0 ]
  [ ! -s "${TEST_TEMP}/curl-invocations.log" ]
}

@test "the actionlint install step reinstalls when the cached version does not match the pin" {
  fake_home="${TEST_TEMP}/fake-home"
  install_fake_tool "${fake_home}" actionlint "1.7.6"
  stub_curl "${TEST_TEMP}/stub-bin" "${TEST_TEMP}/curl-invocations.log"

  run_step "Install actionlint if the pinned version is missing" "${TEST_TEMP}" \
    "HOME=${fake_home}" \
    "PATH=${TEST_TEMP}/stub-bin:${PATH}" \
    "GITHUB_PATH=${TEST_TEMP}/github-path" \
    RUNNER_OS=Linux \
    RUNNER_ARCH=X64 \
    "RUNNER_TEMP=${TEST_TEMP}/runner-temp" \
    ACTIONLINT_VERSION=v1.7.7

  grep -q "actionlint_1.7.7_linux_amd64.tar.gz" "${TEST_TEMP}/curl-invocations.log"
}
