#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  SCANNER="${REPO_ROOT}/.github/actions/repository-security-scan/scan.sh"
  WORKFLOW="${REPO_ROOT}/.github/workflows/repository-security-scan.yml"
  ACTION="${REPO_ROOT}/.github/actions/repository-security-scan/action.yml"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures/repository-security-scan"
  TEST_TEMP="$(mktemp -d)"
  export GITHUB_WORKSPACE="${TEST_TEMP}/workspace"
  export GITHUB_STEP_SUMMARY="${TEST_TEMP}/summary.md"
  export STUB_LOG="${TEST_TEMP}/scanner-invocations.log"
  export ZIZMOR_ARGS_LOG="${TEST_TEMP}/zizmor-args.log"
  STUB_BIN="${TEST_TEMP}/stub-bin"

  mkdir -p \
    "${GITHUB_WORKSPACE}/_target" \
    "${GITHUB_WORKSPACE}/_trusted/.github/security/repository-security" \
    "${STUB_BIN}"
  install_scanner_stubs
  export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
  rm -rf "${TEST_TEMP}"
}

install_scanner_stubs() {
  cat > "${STUB_BIN}/zizmor" << 'STUB'
#!/usr/bin/env bash
set -u
printf 'zizmor\n' >> "${STUB_LOG}"
printf '%s\n' "$*" >> "${ZIZMOR_ARGS_LOG}"
format=plain
no_exit_codes=false
while (($# > 0)); do
  case "$1" in
    --format)
      format="$2"
      shift 2
      ;;
    --no-exit-codes)
      no_exit_codes=true
      shift
      ;;
    *) shift ;;
  esac
done
if grep -R -q 'zizmor-finding' .github 2> /dev/null; then
  if [[ "${format}" == json ]]; then
    printf '[{"rule":"zizmor-fixture"}]\n'
  else
    printf 'zizmor fixture finding\n'
  fi
  [[ "${no_exit_codes}" == true ]] && exit 0
  exit 1
fi
[[ "${format}" == json ]] && printf '[]\n'
exit 0
STUB

  cat > "${STUB_BIN}/actionlint" << 'STUB'
#!/usr/bin/env bash
set -u
printf 'actionlint\n' >> "${STUB_LOG}"
json=false
while (($# > 0)); do
  if [[ "$1" == '--format' ]]; then
    json=true
    shift 2
  else
    shift
  fi
done
if grep -R -q 'actionlint-finding' .github/workflows 2> /dev/null; then
  if [[ "${json}" == true ]]; then
    printf '\n{"kind":"expression","message":"actionlint fixture finding"}\n\n'
  else
    printf '.github/workflows/ci.yml:1:1: actionlint fixture finding\n'
  fi
  exit 1
fi
STUB

  cat > "${STUB_BIN}/shellcheck" << 'STUB'
#!/usr/bin/env bash
set -u
printf 'shellcheck\n' >> "${STUB_LOG}"
json=false
finding=false
for argument in "$@"; do
  [[ "${argument}" == '--format=json1' ]] && json=true
  if [[ -f "${argument}" ]] && grep -q 'shellcheck-finding' "${argument}"; then
    finding=true
  fi
done
if [[ "${finding}" == true ]]; then
  if [[ "${json}" == true ]]; then
    printf '{"comments":[{"code":2086,"message":"shellcheck fixture finding"}]}\n'
  else
    printf 'scripts/tool:2:6: warning: shellcheck fixture finding [SC2086]\n'
  fi
  exit 1
fi
[[ "${json}" == true ]] && printf '{"comments":[]}\n'
exit 0
STUB

  cat > "${STUB_BIN}/checkov" << 'STUB'
#!/usr/bin/env bash
set -u
printf 'checkov\n' >> "${STUB_LOG}"
output_paths=''
while (($# > 0)); do
  if [[ "$1" == '--output-file-path' ]]; then
    output_paths="$2"
    shift 2
  else
    shift
  fi
done
json_path=${output_paths%%,*}
text_path=${output_paths#*,}
if grep -R -q 'checkov-suppressed-finding' . 2> /dev/null; then
  printf '{"summary":{"passed":1,"failed":0,"skipped":1,"resource_count":1},"results":{"skipped_checks":[{"check_id":"CKV_FIXTURE","suppress_comment":"fixture suppression"}]}}\n' > "${json_path}"
  printf 'Passed Checkov fixture scan (1 check skipped via inline suppression)\n' > "${text_path}"
  exit 0
fi
if grep -R -q 'checkov-finding' . 2> /dev/null; then
  printf '{"summary":{"passed":0,"failed":1,"skipped":0,"resource_count":1}}\n' > "${json_path}"
  printf 'Check CKV_FIXTURE failed\n' > "${text_path}"
  exit 1
fi
if find . -type f \( -name '*.tf' -o -name 'Dockerfile' \) -print -quit | grep -q .; then
  printf '{"summary":{"passed":1,"failed":0,"skipped":0,"resource_count":1}}\n' > "${json_path}"
  printf 'Passed Checkov fixture scan\n' > "${text_path}"
else
  printf '{"summary":{"passed":0,"failed":0,"skipped":0,"resource_count":0}}\n' > "${json_path}"
  : > "${text_path}"
fi
STUB

  cat > "${STUB_BIN}/trivy" << 'STUB'
#!/usr/bin/env bash
set -u
command_name=${1:-}
shift || true
if [[ "${command_name}" == convert ]]; then
  output_path=''
  input_path=''
  while (($# > 0)); do
    if [[ "$1" == '--output' ]]; then
      output_path="$2"
      shift 2
    else
      input_path="$1"
      shift
    fi
  done
  if grep -q 'fixture-finding' "${input_path}" 2> /dev/null; then
    printf 'Trivy fixture finding\n' > "${output_path}"
  else
    printf 'Passed Trivy fixture scan\n' > "${output_path}"
  fi
  exit 0
fi

scanner_kind=''
output_path=''
while (($# > 0)); do
  case "$1" in
    --scanners)
      scanner_kind="$2"
      shift 2
      ;;
    --output)
      output_path="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done
printf 'trivy-%s\n' "${scanner_kind}" >> "${STUB_LOG}"
finding=false
if [[ "${scanner_kind}" == vuln ]] && grep -R -q 'vulnerable-dependency-fixture' . 2> /dev/null; then
  finding=true
fi
if [[ "${scanner_kind}" == secret ]] && grep -R -q 'committed-secret-fixture' . 2> /dev/null; then
  finding=true
fi
if [[ "${finding}" == true ]]; then
  printf '{"Results":[{"Target":"fixture","Vulnerabilities":[{"Title":"fixture-finding"}]}]}\n' > "${output_path}"
  exit 1
fi
printf '{"Results":[]}\n' > "${output_path}"
STUB

  chmod +x "${STUB_BIN}"/*
}

prepare_fixture() {
  local fixture_name="$1"
  local target="${GITHUB_WORKSPACE}/_target"
  local fixture relative_path output_path

  while IFS= read -r -d '' fixture; do
    relative_path="${fixture#"${FIXTURES}/${fixture_name}/"}"
    output_path="${target}/${relative_path%.fixture}"
    mkdir -p "$(dirname "${output_path}")"
    cp "${fixture}" "${output_path}"
    if [[ "$(head -n 1 "${output_path}")" == '#!fixture '* ]]; then
      sed -i '1s|^#!fixture |#!|' "${output_path}"
    fi
  done < <(find "${FIXTURES}/${fixture_name}" -type f -name '*.fixture' -print0)

  git -C "${target}" init -q
  git -C "${target}" config user.email test@example.com
  git -C "${target}" config user.name 'Test User'
  git -C "${target}" add -A
  git -C "${target}" commit -q -m fixture
}

run_scanners() {
  local operation

  bash "${SCANNER}" prepare
  bash "${SCANNER}" preflight
  for operation in zizmor actionlint shellcheck checkov trivy-vulnerability trivy-secret; do
    bash "${SCANNER}" "${operation}"
  done
}

assert_fixture_fails_gate() {
  local fixture_name="$1"
  local failed_gate="$2"
  local scanner_name

  prepare_fixture "${fixture_name}"
  run_scanners
  run bash "${SCANNER}" enforce

  [ "${status}" -ne 0 ]
  [ "$(< "${GITHUB_WORKSPACE}/security-results/${failed_gate}.status")" -ne 0 ]
  for scanner_name in zizmor actionlint shellcheck checkov trivy-vulnerability trivy-secret; do
    if [[ "${scanner_name}" != "${failed_gate}" ]]; then
      [ "$(< "${GITHUB_WORKSPACE}/security-results/${scanner_name}.status")" -eq 0 ]
    fi
  done
}

@test "a clean repository passes every scanner and retains complete evidence" {
  prepare_fixture clean
  run_scanners
  run bash "${SCANNER}" enforce

  [ "${status}" -eq 0 ]
  for scanner_name in zizmor actionlint shellcheck checkov trivy-vulnerability trivy-secret; do
    [ "$(< "${GITHUB_WORKSPACE}/security-results/${scanner_name}.status")" -eq 0 ]
    [ -s "${GITHUB_WORKSPACE}/security-results/${scanner_name}.json" ]
    [ -s "${GITHUB_WORKSPACE}/security-results/${scanner_name}.txt" ]
    [ -f "${GITHUB_WORKSPACE}/security-results/${scanner_name}.log" ]
    yq eval --input-format=json '.' \
      "${GITHUB_WORKSPACE}/security-results/${scanner_name}.json" > /dev/null
  done
}

@test "a zizmor finding fails only the zizmor status" {
  assert_fixture_fails_gate zizmor-finding zizmor
}

@test "zizmor is invoked with --no-ignores so target-owned ignore comments cannot suppress findings" {
  prepare_fixture clean
  run_scanners

  [ -s "${ZIZMOR_ARGS_LOG}" ]
  while IFS= read -r invocation_args; do
    [[ "${invocation_args}" == *'--no-ignores'* ]]
  done < "${ZIZMOR_ARGS_LOG}"
}

@test "zizmor receives local action manifests outside .github/actions" {
  prepare_fixture local-action-outside-github-actions
  run_scanners

  [ -s "${ZIZMOR_ARGS_LOG}" ]
  grep -q 'actions/deploy/action.yml' "${ZIZMOR_ARGS_LOG}"
}

@test "an actionlint or embedded ShellCheck diagnostic fails the actionlint status" {
  assert_fixture_fails_gate actionlint-finding actionlint
}

@test "blank lines in actionlint JSON Lines output still produce a valid JSON array" {
  assert_fixture_fails_gate actionlint-finding actionlint

  yq eval --input-format=json '.' "${GITHUB_WORKSPACE}/security-results/actionlint.json" > /dev/null
  [ "$(yq eval --input-format=json '. | length' "${GITHUB_WORKSPACE}/security-results/actionlint.json")" -eq 1 ]
}

@test "an extensionless shebang script diagnostic fails standalone ShellCheck" {
  assert_fixture_fails_gate shellcheck-finding shellcheck
  grep -q 'shellcheck fixture finding' "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
}

@test "an extensionless env -i shebang script is still detected by standalone ShellCheck" {
  assert_fixture_fails_gate env-i-shebang shellcheck
  grep -q 'shellcheck fixture finding' "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
}

@test "an unreadable extensionless script fails standalone ShellCheck closed" {
  if [[ "${EUID}" -eq 0 ]]; then
    skip 'cannot simulate an unreadable file while running as root'
  fi
  prepare_fixture no-relevant-files
  printf '#!/usr/bin/env bash\necho hi\n' > "${GITHUB_WORKSPACE}/_target/unreadable-tool"
  git -C "${GITHUB_WORKSPACE}/_target" add unreadable-tool
  git -C "${GITHUB_WORKSPACE}/_target" commit -q -m 'add unreadable tool'
  chmod 000 "${GITHUB_WORKSPACE}/_target/unreadable-tool"

  run_scanners
  run bash "${SCANNER}" enforce
  chmod 644 "${GITHUB_WORKSPACE}/_target/unreadable-tool"

  [ "${status}" -ne 0 ]
  [ "$(< "${GITHUB_WORKSPACE}/security-results/shellcheck.status")" -eq 1 ]
  grep -q 'unreadable-tool' "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
}

@test "a Checkov infrastructure-as-code finding fails the Checkov status" {
  assert_fixture_fails_gate checkov-finding checkov
}

@test "a Checkov inline suppression comment fails the Checkov status even though Checkov itself passed" {
  assert_fixture_fails_gate checkov-inline-suppression checkov
  grep -q 'inline suppression' "${GITHUB_WORKSPACE}/security-results/checkov.txt"
}

@test "a high-severity vulnerable dependency fails Trivy vulnerability scanning" {
  assert_fixture_fails_gate vulnerable-dependency trivy-vulnerability
}

@test "a committed secret fails Trivy secret scanning" {
  assert_fixture_fails_gate committed-secret trivy-secret
}

@test "a repository without relevant files reports successful skips" {
  prepare_fixture no-relevant-files
  run_scanners
  run bash "${SCANNER}" enforce

  [ "${status}" -eq 0 ]
  grep -q '^Skipped:' "${GITHUB_WORKSPACE}/security-results/zizmor.txt"
  grep -q '^Skipped:' "${GITHUB_WORKSPACE}/security-results/actionlint.txt"
  grep -q '^Skipped:' "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
  grep -q '^Skipped:' "${GITHUB_WORKSPACE}/security-results/checkov.txt"
}

@test "tracked symlinks are removed before every scanner runs" {
  prepare_fixture no-relevant-files
  printf 'outside fixture\n' > "${TEST_TEMP}/outside"
  ln -s "${TEST_TEMP}/outside" "${GITHUB_WORKSPACE}/_target/escape.sh"
  git -C "${GITHUB_WORKSPACE}/_target" add escape.sh

  run_scanners
  run bash "${SCANNER}" enforce

  [ "${status}" -eq 0 ]
  [ ! -e "${GITHUB_WORKSPACE}/_target/escape.sh" ]
  grep -q 'escape.sh' "${GITHUB_WORKSPACE}/security-results/rejected-symlinks.txt"
}

@test "simultaneous findings still execute every scanner before enforcement" {
  prepare_fixture simultaneous-findings
  run_scanners
  run bash "${SCANNER}" enforce

  [ "${status}" -ne 0 ]
  for scanner_name in zizmor actionlint shellcheck checkov trivy-vulnerability trivy-secret; do
    [ "$(< "${GITHUB_WORKSPACE}/security-results/${scanner_name}.status")" -ne 0 ]
  done
  for invocation in zizmor actionlint shellcheck checkov trivy-vuln trivy-secret; do
    grep -q "^${invocation}$" "${STUB_LOG}"
  done
}

@test "missing or invalid evidence fails closed" {
  prepare_fixture clean
  run_scanners
  rm "${GITHUB_WORKSPACE}/security-results/actionlint.json"
  printf 'not-a-status\n' > "${GITHUB_WORKSPACE}/security-results/checkov.status"

  run bash "${SCANNER}" enforce

  [ "${status}" -ne 0 ]
  [[ "${output}" == *'actionlint did not produce required evidence'* ]]
  [[ "${output}" == *'checkov gate failed with status not-a-status'* ]]
}

@test "the workflow defers direct pull_request/merge_group activation to a follow-up" {
  [ "$(yq eval '.on | keys | join(",")' "${WORKFLOW}")" = workflow_call ]
  yq eval --exit-status '.on | has("pull_request") | not' "${WORKFLOW}" > /dev/null
  yq eval --exit-status '.on | has("merge_group") | not' "${WORKFLOW}" > /dev/null
}

@test "the workflow preserves reusable, merge-group, fork, and read-only boundaries" {
  yq eval --exit-status '.permissions.contents == "read" and (.permissions | length == 1)' "${WORKFLOW}" > /dev/null
  yq eval --exit-status '.jobs.scan.permissions.contents == "read" and (.jobs.scan.permissions | length == 1)' "${WORKFLOW}" > /dev/null
  [ "$(yq eval '[.jobs.scan.steps[] | select(.uses == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1") | select(.with."persist-credentials" != false)] | length' "${WORKFLOW}")" -eq 0 ]
  grep -q 'github.event.merge_group.head_sha' "${WORKFLOW}"
  grep -q 'github.event.pull_request.head.sha' "${WORKFLOW}"
  grep -q 'github.event.pull_request.base.sha' "${WORKFLOW}"
  grep -q 'repository: .*job.workflow_repository' "${WORKFLOW}"
  grep -q 'job.workflow_sha' "${WORKFLOW}"
  run ! grep -q 'ref: .*github.workflow_sha' "${WORKFLOW}"
  run ! grep -q 'pull_request_target' "${WORKFLOW}"
}

@test "the composite action always retains evidence before one aggregate gate" {
  [ "$(yq eval '.runs.steps[-2].uses' "${ACTION}")" = 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' ]
  [ "$(yq eval '.runs.steps[-1].name' "${ACTION}")" = 'Enforce aggregate scanner result' ]
  [ "$(yq eval '[.runs.steps[] | select(.name | test("^Run .* gate$")) | select(.if != "always()")] | length' "${ACTION}")" -eq 0 ]
  [ "$(yq eval '.runs.steps[-2].with."if-no-files-found"' "${ACTION}")" = error ]
}
