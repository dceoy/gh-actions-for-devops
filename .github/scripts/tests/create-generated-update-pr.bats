#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  ACTION_DIR="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)/.github/actions/create-generated-update-pr"
  TEST_TEMP="$(mktemp -d)"
  ORIGIN="${TEST_TEMP}/origin.git"
  REPO="${TEST_TEMP}/repo"
  GH_STUB_DIR="${TEST_TEMP}/bin"
  GH_STUB_LOG="${TEST_TEMP}/gh-invocations.log"
  GITHUB_OUTPUT_FILE="${TEST_TEMP}/github-output"
  : > "${GITHUB_OUTPUT_FILE}"
  : > "${GH_STUB_LOG}"

  git init -q --bare "${ORIGIN}"

  git init -q -b main "${REPO}"
  git -C "${REPO}" config user.name "Test User"
  git -C "${REPO}" config user.email test@example.com
  mkdir -p "${REPO}/generated" "${REPO}/other"
  echo "initial" > "${REPO}/generated/output.txt"
  echo "initial" > "${REPO}/other/unrelated.txt"
  git -C "${REPO}" add .
  git -C "${REPO}" commit -q -m "Initial commit"
  git -C "${REPO}" remote add origin "${ORIGIN}"
  git -C "${REPO}" push -q origin main

  mkdir -p "${GH_STUB_DIR}"
  cat > "${GH_STUB_DIR}/gh" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GH_STUB_LOG}"
case "${1:-} ${2:-}" in
  "auth setup-git") ;;
  "pr list")
    printf '%s' "${GH_STUB_PR_LIST_OUTPUT:-}"
    ;;
  "pr create") ;;
  "pr edit") ;;
  "pr view")
    if [[ "$*" == *"number"* ]]; then
      printf '%s' "${GH_STUB_PR_NUMBER:-42}"
    else
      printf '%s' "${GH_STUB_PR_URL:-https://example.invalid/pr/42}"
    fi
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "${GH_STUB_DIR}/gh"
}

teardown() {
  rm -rf "${TEST_TEMP}"
}

run_script() {
  local script="$1"
  shift
  run env "$@" GITHUB_OUTPUT="${GITHUB_OUTPUT_FILE}" bash "${ACTION_DIR}/scripts/${script}"
}

output_value() {
  local key="$1"
  grep "^${key}=" "${GITHUB_OUTPUT_FILE}" | tail -n1 | cut -d= -f2-
}

@test "stage-changes reports changed=false when scoped paths are untouched" {
  cd "${REPO}"
  echo "unrelated edit" >> other/unrelated.txt
  run_script stage-changes.sh PATHS=$'generated/*'

  [ "${status}" -eq 0 ]
  [ "$(output_value changed)" = "false" ]
}

@test "stage-changes stages only caller-scoped pathspecs" {
  cd "${REPO}"
  echo "generated edit" >> generated/output.txt
  echo "unrelated edit" >> other/unrelated.txt
  run_script stage-changes.sh PATHS=$'generated/*'

  [ "${status}" -eq 0 ]
  [ "$(output_value changed)" = "true" ]
  staged="$(git diff --cached --name-only)"
  [ "${staged}" = "generated/output.txt" ]
}

@test "stage-changes fails when paths input is empty" {
  cd "${REPO}"
  run_script stage-changes.sh PATHS=

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"paths input must not be empty"* ]]
}

@test "commit-and-push creates the branch, commits, and pushes to origin" {
  cd "${REPO}"
  echo "generated edit" >> generated/output.txt
  git add -- generated/output.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=update-generated \
    COMMIT_MESSAGE='Update generated files' \
    GIT_USER_NAME='Bot' \
    GIT_USER_EMAIL='bot@example.com' \
    PATHS=$'generated/*'

  [ "${status}" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "update-generated" ]
  commit_sha="$(output_value commit-sha)"
  [ -n "${commit_sha}" ]
  [ "$(git rev-parse HEAD)" = "${commit_sha}" ]
  remote_sha="$(git ls-remote origin refs/heads/update-generated | cut -f1)"
  [ "${remote_sha}" = "${commit_sha}" ]
  grep -q '^auth setup-git' "${GH_STUB_LOG}"
}

@test "commit-and-push commits only the caller-scoped pathspecs, leaving other staged files staged" {
  cd "${REPO}"
  echo "generated edit" >> generated/output.txt
  echo "unrelated staged edit" >> other/unrelated.txt
  git add -- generated/output.txt other/unrelated.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=update-generated \
    COMMIT_MESSAGE='Update generated files' \
    GIT_USER_NAME='Bot' \
    GIT_USER_EMAIL='bot@example.com' \
    PATHS=$'generated/*'

  [ "${status}" -eq 0 ]
  committed="$(git show --name-only --pretty=format: HEAD)"
  [ "${committed}" = "generated/output.txt" ]
  staged="$(git diff --cached --name-only)"
  [ "${staged}" = "other/unrelated.txt" ]
}

@test "commit-and-push fails when paths input is empty" {
  cd "${REPO}"
  echo "generated edit" >> generated/output.txt
  git add -- generated/output.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=update-generated \
    COMMIT_MESSAGE='Update generated files' \
    GIT_USER_NAME='Bot' \
    GIT_USER_EMAIL='bot@example.com' \
    PATHS=

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"paths input must not be empty"* ]]
  [ ! -s "${GH_STUB_LOG}" ]
}

@test "commit-and-push resets a previously pushed branch instead of accumulating commits" {
  cd "${REPO}"
  echo "first" >> generated/output.txt
  git add -- generated/output.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=update-generated \
    COMMIT_MESSAGE='first update' \
    GIT_USER_NAME='Bot' \
    GIT_USER_EMAIL='bot@example.com' \
    PATHS=$'generated/*'
  [ "${status}" -eq 0 ]
  first_sha="$(output_value commit-sha)"

  git checkout -q main
  echo "second" >> generated/output.txt
  git add -- generated/output.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=update-generated \
    COMMIT_MESSAGE='second update' \
    GIT_USER_NAME='Bot' \
    GIT_USER_EMAIL='bot@example.com' \
    PATHS=$'generated/*'
  [ "${status}" -eq 0 ]
  second_sha="$(output_value commit-sha)"

  [ "${first_sha}" != "${second_sha}" ]
  [ "$(git rev-list --count update-generated)" -eq 2 ]
  remote_sha="$(git ls-remote origin refs/heads/update-generated | cut -f1)"
  [ "${remote_sha}" = "${second_sha}" ]
}

@test "commit-and-push rejects a branch name that looks like a flag" {
  cd "${REPO}"
  echo "edit" >> generated/output.txt
  git add -- generated/output.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH='--upload-pack=touch /tmp/create-generated-update-pr-pwned' \
    COMMIT_MESSAGE=m \
    GIT_USER_NAME=Bot \
    GIT_USER_EMAIL=bot@example.com

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a valid Git branch name"* ]]
  [ ! -f /tmp/create-generated-update-pr-pwned ]
  [ ! -s "${GH_STUB_LOG}" ]
}

@test "commit-and-push fails when GH_TOKEN is not set" {
  cd "${REPO}"
  echo "edit" >> generated/output.txt
  git add -- generated/output.txt
  run env -u GH_TOKEN \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GITHUB_OUTPUT="${GITHUB_OUTPUT_FILE}" \
    BRANCH=update-generated \
    COMMIT_MESSAGE=m \
    GIT_USER_NAME=Bot \
    GIT_USER_EMAIL=bot@example.com \
    bash "${ACTION_DIR}/scripts/commit-and-push.sh"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"GH_TOKEN must be set"* ]]
  [ ! -s "${GH_STUB_LOG}" ]
}

@test "create-or-update-pr creates a new pull request when none is open" {
  cd "${REPO}"
  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_PR_LIST_OUTPUT='' \
    GH_STUB_PR_NUMBER=101 \
    GH_STUB_PR_URL='https://example.invalid/pr/101' \
    BRANCH=update-generated \
    BASE=main \
    TITLE='Update generated files' \
    BODY='body text' \
    LABELS='automated,generated' \
    DRAFT=false

  [ "${status}" -eq 0 ]
  [ "$(output_value pr-number)" = "101" ]
  [ "$(output_value pr-url)" = "https://example.invalid/pr/101" ]
  grep -q '^pr create ' "${GH_STUB_LOG}"
  grep -q -- '--label automated' "${GH_STUB_LOG}"
  grep -q -- '--label generated' "${GH_STUB_LOG}"
  run ! grep -q '^pr edit ' "${GH_STUB_LOG}"
}

@test "create-or-update-pr updates the existing open pull request" {
  cd "${REPO}"
  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_PR_LIST_OUTPUT=77 \
    GH_STUB_PR_NUMBER=77 \
    GH_STUB_PR_URL='https://example.invalid/pr/77' \
    BRANCH=update-generated \
    BASE=main \
    TITLE='Update generated files' \
    BODY='body text' \
    LABELS='automated' \
    DRAFT=false

  [ "${status}" -eq 0 ]
  [ "$(output_value pr-number)" = "77" ]
  grep -q '^pr edit 77 ' "${GH_STUB_LOG}"
  grep -q -- '--add-label automated' "${GH_STUB_LOG}"
  run ! grep -q '^pr create ' "${GH_STUB_LOG}"
}

@test "create-or-update-pr fails when GH_TOKEN is not set" {
  cd "${REPO}"
  run env -u GH_TOKEN \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GITHUB_OUTPUT="${GITHUB_OUTPUT_FILE}" \
    BRANCH=update-generated \
    BASE=main \
    TITLE='Update generated files' \
    bash "${ACTION_DIR}/scripts/create-or-update-pr.sh"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"GH_TOKEN must be set"* ]]
}

@test "create-or-update-pr rejects a branch name that looks like a flag" {
  cd "${REPO}"
  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH='--upload-pack=touch /tmp/create-generated-update-pr-pwned' \
    BASE=main \
    TITLE='Update generated files'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a valid Git branch name"* ]]
  [ ! -s "${GH_STUB_LOG}" ]
}
