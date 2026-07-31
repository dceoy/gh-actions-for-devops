#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  ACTION_DIR="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)/.github/actions/create-generated-update-pr"
  TEST_TEMP="$(mktemp -d)"
  ORIGIN="${TEST_TEMP}/origin.git"
  REPO="${TEST_TEMP}/repo"
  GH_STUB_DIR="${TEST_TEMP}/bin"
  GH_STUB_LOG="${TEST_TEMP}/gh-invocations.log"
  GH_STUB_CREATED_MARKER="${TEST_TEMP}/pr-created"
  GITHUB_OUTPUT_FILE="${TEST_TEMP}/github-output"
  export GITHUB_REPOSITORY="owner/repo"
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
  "api repos/"*)
    printf '%s' "${GH_STUB_COMPARE_STATUS:-identical}"
    ;;
  "pr list")
    if [[ -f "${GH_STUB_CREATED_MARKER:-}" ]]; then
      printf '%s' "${GH_STUB_PR_NUMBER:-42}"
    elif [[ -n "${GH_STUB_PR_LIST_JSON:-}" ]]; then
      jq_filter=""
      args=("$@")
      for ((i = 0; i < ${#args[@]}; i++)); do
        if [[ "${args[${i}]}" == "--jq" ]]; then
          jq_filter="${args[$((i + 1))]}"
        fi
      done
      printf '%s' "${GH_STUB_PR_LIST_JSON}" | jq -r "${jq_filter}"
    else
      printf '%s' "${GH_STUB_PR_LIST_OUTPUT:-}"
    fi
    ;;
  "pr create")
    [[ -n "${GH_STUB_CREATED_MARKER:-}" ]] && : > "${GH_STUB_CREATED_MARKER}"
    true
    ;;
  "pr edit") ;;
  "pr ready") ;;
  "pr close") ;;
  "pr view")
    if [[ "$*" == *"isDraft"* ]]; then
      printf '%s' "${GH_STUB_PR_IS_DRAFT:-false}"
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

@test "stage-changes reports changed=false when the pathspec matches nothing" {
  cd "${REPO}"
  run_script stage-changes.sh PATHS=$'nonexistent/*'

  [ "${status}" -eq 0 ]
  [ "$(output_value changed)" = "false" ]
}

@test "stage-changes stages a new untracked file matching the pathspec" {
  cd "${REPO}"
  echo "new" > generated/new-file.txt
  run_script stage-changes.sh PATHS=$'generated/*'

  [ "${status}" -eq 0 ]
  [ "$(output_value changed)" = "true" ]
  staged="$(git diff --cached --name-only)"
  [ "${staged}" = "generated/new-file.txt" ]
}

@test "stage-changes fails when paths input is empty" {
  cd "${REPO}"
  run_script stage-changes.sh PATHS=

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"paths input must not be empty"* ]]
}

@test "stage-changes fails when paths input contains only blank lines" {
  cd "${REPO}"
  run_script stage-changes.sh PATHS=$'\n\n'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"paths input produced no pathspecs"* ]]
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
    BASE=main \
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
    BASE=main \
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
    BASE=main \
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
    BASE=main \
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
    BASE=main \
    COMMIT_MESSAGE='second update' \
    GIT_USER_NAME='Bot' \
    GIT_USER_EMAIL='bot@example.com' \
    PATHS=$'generated/*'
  [ "${status}" -eq 0 ]
  second_sha="$(output_value commit-sha)"

  [ "${first_sha}" != "${second_sha}" ]
  [ "$(git rev-list --count update-generated)" -eq "$(($(git rev-list --count main) + 1))" ]
  remote_sha="$(git ls-remote origin refs/heads/update-generated | cut -f1)"
  [ "${remote_sha}" = "${second_sha}" ]
}

@test "commit-and-push skips the push when a rerun produces an identical tree" {
  cd "${REPO}"
  echo "first" >> generated/output.txt
  git add -- generated/output.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=update-generated \
    BASE=main \
    COMMIT_MESSAGE='first update' \
    GIT_USER_NAME='Bot' \
    GIT_USER_EMAIL='bot@example.com' \
    PATHS=$'generated/*'
  [ "${status}" -eq 0 ]
  first_sha="$(output_value commit-sha)"
  remote_sha_after_first="$(git ls-remote origin refs/heads/update-generated | cut -f1)"

  git checkout -q main
  echo "first" >> generated/output.txt
  git add -- generated/output.txt
  : > "${GITHUB_OUTPUT_FILE}"
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=update-generated \
    BASE=main \
    COMMIT_MESSAGE='second update, same content' \
    GIT_USER_NAME='Bot' \
    GIT_USER_EMAIL='bot@example.com' \
    PATHS=$'generated/*'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"skipping push"* ]]
  second_sha="$(output_value commit-sha)"

  [ "${second_sha}" = "${first_sha}" ]
  remote_sha_after_second="$(git ls-remote origin refs/heads/update-generated | cut -f1)"
  [ "${remote_sha_after_second}" = "${remote_sha_after_first}" ]
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
    BASE=main \
    COMMIT_MESSAGE=m \
    GIT_USER_NAME=Bot \
    GIT_USER_EMAIL=bot@example.com

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a valid Git branch name"* ]]
  [ ! -f /tmp/create-generated-update-pr-pwned ]
  [ ! -s "${GH_STUB_LOG}" ]
}

@test "commit-and-push rejects checkout shorthand that resolves to another branch" {
  cd "${REPO}"
  git checkout -q -b decoy
  echo "edit" >> generated/output.txt
  git add -- generated/output.txt
  before_local_main="$(git rev-parse main)"
  before_remote_main="$(git -C "${ORIGIN}" rev-parse main)"

  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH='@{-1}' \
    BASE=main \
    COMMIT_MESSAGE=m \
    GIT_USER_NAME=Bot \
    GIT_USER_EMAIL=bot@example.com \
    PATHS=$'generated/*'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a valid Git branch name"* ]]
  [ ! -s "${GH_STUB_LOG}" ]
  [ "$(git rev-parse main)" = "${before_local_main}" ]
  [ "$(git -C "${ORIGIN}" rev-parse main)" = "${before_remote_main}" ]
}

@test "commit-and-push refuses to force-push when branch equals base" {
  cd "${REPO}"
  echo "edit" >> generated/output.txt
  git add -- generated/output.txt
  before_sha="$(git -C "${ORIGIN}" rev-parse main)"
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=main \
    BASE=main \
    COMMIT_MESSAGE=m \
    GIT_USER_NAME=Bot \
    GIT_USER_EMAIL=bot@example.com \
    PATHS=$'generated/*'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"branch must not be the same as base"* ]]
  [ ! -s "${GH_STUB_LOG}" ]
  [ "$(git -C "${ORIGIN}" rev-parse main)" = "${before_sha}" ]
}

@test "commit-and-push fails when the checked-out commit is not based on base" {
  cd "${REPO}"
  echo "edit" >> generated/output.txt
  git add -- generated/output.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_COMPARE_STATUS=diverged \
    BRANCH=update-generated \
    BASE=main \
    COMMIT_MESSAGE=m \
    GIT_USER_NAME=Bot \
    GIT_USER_EMAIL=bot@example.com \
    PATHS=$'generated/*'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"is not based on base"* ]]
  run ! git -C "${REPO}" rev-parse --verify refs/heads/update-generated
  run ! git -C "${ORIGIN}" rev-parse --verify refs/heads/update-generated
}

@test "commit-and-push proceeds when the checked-out commit is behind base" {
  cd "${REPO}"
  echo "edit" >> generated/output.txt
  git add -- generated/output.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_COMPARE_STATUS=behind \
    BRANCH=update-generated \
    BASE=main \
    COMMIT_MESSAGE=m \
    GIT_USER_NAME=Bot \
    GIT_USER_EMAIL=bot@example.com \
    PATHS=$'generated/*'

  [ "${status}" -eq 0 ]
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
    BASE=main \
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
    GH_STUB_CREATED_MARKER="${GH_STUB_CREATED_MARKER}" \
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

@test "create-or-update-pr creates a new pull request as a draft" {
  cd "${REPO}"
  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_CREATED_MARKER="${GH_STUB_CREATED_MARKER}" \
    GH_STUB_PR_LIST_OUTPUT='' \
    GH_STUB_PR_NUMBER=102 \
    GH_STUB_PR_URL='https://example.invalid/pr/102' \
    BRANCH=update-generated \
    BASE=main \
    TITLE='Update generated files' \
    BODY='body text' \
    LABELS='' \
    DRAFT=true

  [ "${status}" -eq 0 ]
  grep -q -- '^pr create.*--draft' "${GH_STUB_LOG}"
}

@test "create-or-update-pr resolves an all-numeric branch name without an ambiguous positional argument" {
  cd "${REPO}"
  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_CREATED_MARKER="${GH_STUB_CREATED_MARKER}" \
    GH_STUB_PR_LIST_OUTPUT='' \
    GH_STUB_PR_NUMBER=999 \
    GH_STUB_PR_URL='https://example.invalid/pr/999' \
    BRANCH=123 \
    BASE=main \
    TITLE='Update generated files' \
    BODY='body text' \
    LABELS='' \
    DRAFT=false

  [ "${status}" -eq 0 ]
  [ "$(output_value pr-number)" = "999" ]
  run ! grep -q '^pr view 123' "${GH_STUB_LOG}"
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
    GH_STUB_PR_IS_DRAFT=false \
    BRANCH=update-generated \
    BASE=main \
    TITLE='Update generated files' \
    BODY='body text' \
    LABELS='automated' \
    DRAFT=false

  [ "${status}" -eq 0 ]
  [ "$(output_value pr-number)" = "77" ]
  grep -q '^pr edit 77 ' "${GH_STUB_LOG}"
  grep -q -- '--base main' "${GH_STUB_LOG}"
  grep -q -- '--add-label automated' "${GH_STUB_LOG}"
  run ! grep -q '^pr create ' "${GH_STUB_LOG}"
  run ! grep -q '^pr ready ' "${GH_STUB_LOG}"
  pr_list_line="$(grep '^pr list' "${GH_STUB_LOG}")"
  [[ "${pr_list_line}" == 'pr list --head update-generated --state open '* ]]
}

@test "create-or-update-pr skips a fork pull request with the same head branch name" {
  cd "${REPO}"
  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_PR_LIST_JSON='[{"number":55,"isCrossRepository":true},{"number":77,"isCrossRepository":false}]' \
    GH_STUB_PR_URL='https://example.invalid/pr/77' \
    GH_STUB_PR_IS_DRAFT=false \
    BRANCH=update-generated \
    BASE=main \
    TITLE='Update generated files' \
    BODY='body text' \
    LABELS='' \
    DRAFT=false

  [ "${status}" -eq 0 ]
  [ "$(output_value pr-number)" = "77" ]
  grep -q '^pr edit 77 ' "${GH_STUB_LOG}"
  run ! grep -q '^pr edit 55 ' "${GH_STUB_LOG}"
}

@test "create-or-update-pr retargets base and un-drafts an existing pull request" {
  cd "${REPO}"
  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_PR_LIST_OUTPUT=77 \
    GH_STUB_PR_NUMBER=77 \
    GH_STUB_PR_URL='https://example.invalid/pr/77' \
    GH_STUB_PR_IS_DRAFT=true \
    BRANCH=update-generated \
    BASE=develop \
    TITLE='Update generated files' \
    BODY='body text' \
    LABELS='' \
    DRAFT=false

  [ "${status}" -eq 0 ]
  grep -q -- '--base develop' "${GH_STUB_LOG}"
  grep -q '^pr ready 77 *$' "${GH_STUB_LOG}"
  run ! grep -q -- '--undo' "${GH_STUB_LOG}"
}

@test "create-or-update-pr converts an existing pull request to draft" {
  cd "${REPO}"
  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_PR_LIST_OUTPUT=77 \
    GH_STUB_PR_NUMBER=77 \
    GH_STUB_PR_URL='https://example.invalid/pr/77' \
    GH_STUB_PR_IS_DRAFT=false \
    BRANCH=update-generated \
    BASE=main \
    TITLE='Update generated files' \
    BODY='body text' \
    LABELS='' \
    DRAFT=true

  [ "${status}" -eq 0 ]
  grep -q -- '^pr ready 77 --undo' "${GH_STUB_LOG}"
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

@test "create-or-update-pr rejects a base that looks like a flag" {
  cd "${REPO}"
  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=update-generated \
    BASE='--upload-pack=touch /tmp/create-generated-update-pr-pwned' \
    TITLE='Update generated files'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a valid Git branch name"* ]]
  [ ! -f /tmp/create-generated-update-pr-pwned ]
  [ ! -s "${GH_STUB_LOG}" ]
}

@test "close-obsolete-pr closes an existing open pull request" {
  cd "${REPO}"
  run_script close-obsolete-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_PR_LIST_OUTPUT=77 \
    BRANCH=update-generated

  [ "${status}" -eq 0 ]
  grep -q '^pr close 77 ' "${GH_STUB_LOG}"
}

@test "close-obsolete-pr does nothing when no pull request is open" {
  cd "${REPO}"
  run_script close-obsolete-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_PR_LIST_OUTPUT='' \
    BRANCH=update-generated

  [ "${status}" -eq 0 ]
  run ! grep -q '^pr close ' "${GH_STUB_LOG}"
}

@test "close-obsolete-pr skips a fork pull request with the same head branch name" {
  cd "${REPO}"
  run_script close-obsolete-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_PR_LIST_JSON='[{"number":55,"isCrossRepository":true}]' \
    BRANCH=update-generated

  [ "${status}" -eq 0 ]
  run ! grep -q '^pr close ' "${GH_STUB_LOG}"
}

@test "close-obsolete-pr rejects a branch name that looks like a flag" {
  cd "${REPO}"
  run_script close-obsolete-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH='--upload-pack=touch /tmp/create-generated-update-pr-pwned'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a valid Git branch name"* ]]
  [ ! -f /tmp/create-generated-update-pr-pwned ]
  [ ! -s "${GH_STUB_LOG}" ]
}

@test "close-obsolete-pr rejects checkout shorthand that resolves to another branch" {
  cd "${REPO}"
  git checkout -q -b decoy

  run_script close-obsolete-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH='@{-1}'

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not a valid Git branch name"* ]]
  [ ! -s "${GH_STUB_LOG}" ]
}

@test "close-obsolete-pr fails when GH_TOKEN is not set" {
  cd "${REPO}"
  run env -u GH_TOKEN \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GITHUB_OUTPUT="${GITHUB_OUTPUT_FILE}" \
    BRANCH=update-generated \
    bash "${ACTION_DIR}/scripts/close-obsolete-pr.sh"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"GH_TOKEN must be set"* ]]
}

@test "an update pull request opened by an earlier run is closed once the scoped diff disappears" {
  cd "${REPO}"
  echo "generated edit" >> generated/output.txt
  git add -- generated/output.txt
  run_script commit-and-push.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    BRANCH=update-generated \
    BASE=main \
    COMMIT_MESSAGE='Update generated files' \
    GIT_USER_NAME='Bot' \
    GIT_USER_EMAIL='bot@example.com' \
    PATHS=$'generated/*'
  [ "${status}" -eq 0 ]

  run_script create-or-update-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_CREATED_MARKER="${GH_STUB_CREATED_MARKER}" \
    GH_STUB_PR_LIST_OUTPUT='' \
    GH_STUB_PR_NUMBER=101 \
    GH_STUB_PR_URL='https://example.invalid/pr/101' \
    BRANCH=update-generated \
    BASE=main \
    TITLE='Update generated files' \
    BODY='body text'
  [ "${status}" -eq 0 ]
  [ "$(output_value pr-number)" = "101" ]

  git -C "${REPO}" checkout -q main
  run_script stage-changes.sh PATHS=$'generated/*'
  [ "${status}" -eq 0 ]
  [ "$(output_value changed)" = "false" ]

  run_script close-obsolete-pr.sh \
    "PATH=${GH_STUB_DIR}:${PATH}" \
    GH_TOKEN=test-token \
    GH_STUB_LOG="${GH_STUB_LOG}" \
    GH_STUB_CREATED_MARKER="${GH_STUB_CREATED_MARKER}" \
    GH_STUB_PR_NUMBER=101 \
    BRANCH=update-generated
  [ "${status}" -eq 0 ]
  grep -q '^pr close 101 ' "${GH_STUB_LOG}"
}
