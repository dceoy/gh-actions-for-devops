#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  SCANNER="${REPO_ROOT}/.github/actions/repository-security-scan/scan.sh"
  WORKFLOW="${REPO_ROOT}/.github/workflows/repository-security-scan.yml"
  ACTION="${REPO_ROOT}/.github/actions/repository-security-scan/action.yml"
  TRIVY_SECRET_CONFIG="${REPO_ROOT}/.github/security/repository-security/trivy-secret.yaml"
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
  cp "${TRIVY_SECRET_CONFIG}" \
    "${GITHUB_WORKSPACE}/_trusted/.github/security/repository-security/trivy-secret.yaml"
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
if grep -R -q 'actionlint-runtime-error' .github/workflows 2> /dev/null; then
  exit 2
fi
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
secret_config=''
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
    --secret-config)
      secret_config="$2"
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
  if grep -R -q --include='*.md' 'committed-secret-fixture' . 2> /dev/null \
    && ! yq eval --exit-status '.disable-allow-rules | contains(["markdown"])' \
      "${secret_config}" > /dev/null; then
    finding=false
  else
    finding=true
  fi
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
    if [[ "$(head -n 1 "${output_path}")" == 'version-fixture '* ]]; then
      sed -i '1s|^version-fixture |version |' "${output_path}"
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

@test "a workflow ShellCheck directive fails the embedded ShellCheck gate closed" {
  assert_fixture_fails_gate actionlint-shellcheck-directive actionlint
  grep -q 'target-owned ShellCheck directives' \
    "${GITHUB_WORKSPACE}/security-results/actionlint.txt"
}

@test "an expression-valued workflow shell fails the embedded ShellCheck gate closed" {
  assert_fixture_fails_gate actionlint-dynamic-shell actionlint
  grep -q 'expression-valued workflow shells are not allowed' \
    "${GITHUB_WORKSPACE}/security-results/actionlint.txt"
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

@test "a standalone script ShellCheck directive fails the gate closed" {
  assert_fixture_fails_gate shellcheck-directive shellcheck
  grep -q 'target-owned ShellCheck directives' \
    "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
}

@test "a composite action run block diagnostic fails standalone ShellCheck" {
  assert_fixture_fails_gate composite-action-shellcheck-finding shellcheck
  grep -q 'shellcheck fixture finding' \
    "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
}

@test "a composite action ShellCheck directive fails the gate closed" {
  assert_fixture_fails_gate composite-action-shellcheck-directive shellcheck
  grep -q 'target-owned ShellCheck directives' \
    "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
}

@test "an expression-valued composite shell fails the gate closed" {
  assert_fixture_fails_gate composite-action-dynamic-shell shellcheck
  grep -q 'expression-valued composite shells are not allowed' \
    "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
}

@test "an extensionless env -i shebang script is still detected by standalone ShellCheck" {
  assert_fixture_fails_gate env-i-shebang shellcheck
  grep -q 'shellcheck fixture finding' "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
}

@test "an extensionless env shebang with an option operand is detected by standalone ShellCheck" {
  assert_fixture_fails_gate env-option-operand-shebang shellcheck
  grep -q 'shellcheck fixture finding' "${GITHUB_WORKSPACE}/security-results/shellcheck.txt"
}

@test "an extensionless env shebang with an assignment is detected by standalone ShellCheck" {
  assert_fixture_fails_gate env-assignment-shebang shellcheck
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

@test "Trivy scans Markdown and disables every built-in path exemption" {
  [ "$(yq eval '.disable-allow-rules | sort | join(",")' "${TRIVY_SECRET_CONFIG}")" = \
    'anaconda-log,dist-info,examples,golang,locale-dir,markdown,node.js,python,rubygems,tests,usr-dirs,vendor,wordpress' ]
  [ "$(yq eval '.skip-patterns | length' "${TRIVY_SECRET_CONFIG}")" -eq 0 ]
  assert_fixture_fails_gate secret-in-markdown trivy-secret
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

@test "a tracked Git LFS pointer fails preflight before any scanner runs" {
  prepare_fixture lfs-pointer

  run_scanners
  run bash "${SCANNER}" enforce

  [ "${status}" -ne 0 ]
  [ "$(< "${GITHUB_WORKSPACE}/security-results/preflight.status")" -eq 1 ]
  grep -q 'large-lockfile' \
    "${GITHUB_WORKSPACE}/security-results/rejected-lfs-pointers.txt"
  for scanner_name in zizmor actionlint shellcheck checkov trivy-vulnerability trivy-secret; do
    [ "$(< "${GITHUB_WORKSPACE}/security-results/${scanner_name}.status")" -eq 125 ]
  done
  [ ! -e "${STUB_LOG}" ]
}

@test "a tracked submodule gitlink fails preflight before any scanner runs" {
  local target submodule_commit scanner_name

  prepare_fixture no-relevant-files
  target="${GITHUB_WORKSPACE}/_target"
  submodule_commit="$(git -C "${target}" rev-parse HEAD)"
  git -C "${target}" update-index --add \
    --cacheinfo "160000,${submodule_commit},vendor/dependency"
  git -C "${target}" commit -q -m 'add submodule fixture'

  run_scanners
  run bash "${SCANNER}" enforce

  [ "${status}" -ne 0 ]
  [ "$(< "${GITHUB_WORKSPACE}/security-results/preflight.status")" -eq 1 ]
  grep -q 'vendor/dependency' \
    "${GITHUB_WORKSPACE}/security-results/rejected-submodules.txt"
  for scanner_name in zizmor actionlint shellcheck checkov trivy-vulnerability trivy-secret; do
    [ "$(< "${GITHUB_WORKSPACE}/security-results/${scanner_name}.status")" -eq 125 ]
  done
  [ ! -e "${STUB_LOG}" ]
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

@test "the workflow activates direct pull_request and merge_group triggers alongside workflow_call" {
  [ "$(yq eval '.on | keys | join(",")' "${WORKFLOW}")" = 'pull_request,merge_group,workflow_call' ]
  yq eval --exit-status '.on.pull_request == null' "${WORKFLOW}" > /dev/null
  yq eval --exit-status '.on.merge_group == null' "${WORKFLOW}" > /dev/null
}

@test "the workflow preserves reusable, merge-group, fork, and read-only boundaries" {
  yq eval --exit-status '.permissions.contents == "read" and (.permissions | length == 1)' "${WORKFLOW}" > /dev/null
  yq eval --exit-status '.jobs.scan.permissions.contents == "read" and (.jobs.scan.permissions | length == 1)' "${WORKFLOW}" > /dev/null
  [ "$(yq eval '[.jobs.scan.steps[] | select(.uses == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1") | select(.with."persist-credentials" != false)] | length' "${WORKFLOW}")" -eq 0 ]
  grep -q 'github.event.merge_group.head_sha' "${WORKFLOW}"
  grep -q 'github.event.merge_group.base_sha' "${WORKFLOW}"
  grep -q 'github.event.pull_request.base.sha' "${WORKFLOW}"
  run ! grep -q 'github.event.pull_request.head.sha' "${WORKFLOW}"
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Check out trusted scanner implementation") | .with.ref' "${WORKFLOW}")" = \
    "\${{ job.workflow_ref == github.workflow_ref && github.event_name == 'pull_request' && github.event.pull_request.base.sha || job.workflow_ref == github.workflow_ref && github.event_name == 'merge_group' && github.event.merge_group.base_sha || job.workflow_sha }}" ]
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Check out untrusted target revision") | .with.ref' "${WORKFLOW}")" = \
    "\${{ inputs.target-repository != '' && steps.target.outputs.ref || (github.event_name == 'merge_group' && github.event.merge_group.head_sha || github.sha) }}" ]
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Check out untrusted target revision") | .with.lfs' "${WORKFLOW}")" = 'false' ]
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Check out untrusted target revision") | .with.submodules' "${WORKFLOW}")" = 'false' ]
  grep -q 'repository: .*job.workflow_repository' "${WORKFLOW}"
  grep -q 'job.workflow_sha' "${WORKFLOW}"
  run ! grep -q 'ref: .*github.workflow_sha' "${WORKFLOW}"
  run ! grep -q 'pull_request_target' "${WORKFLOW}"
}

@test "the composite action always retains evidence before one aggregate gate" {
  [ "$(yq eval '.runs.steps[-2].uses' "${ACTION}")" = 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' ]
  [ "$(yq eval '.runs.steps[-2].with.name' "${ACTION}")" = \
    "\${{ inputs.evidence-artifact-name != '' && inputs.evidence-artifact-name || format('repository-security-reports-{0}', github.run_attempt) }}" ]
  [ "$(yq eval '.runs.steps[-1].name' "${ACTION}")" = 'Enforce aggregate scanner result' ]
  [ "$(yq eval '[.runs.steps[] | select(.name | test("^Run .* gate$")) | select(.if != "always()")] | length' "${ACTION}")" -eq 0 ]
  [ "$(yq eval '.runs.steps[-2].with."if-no-files-found"' "${ACTION}")" = error ]
}

@test "the workflow never lets an explicit target repository influence the trusted scanner revision" {
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Check out trusted scanner implementation") | .with.repository' "${WORKFLOW}")" \
    = "\${{ job.workflow_repository }}" ]
  run ! grep -q 'target-repository' <(yq eval '.jobs.scan.steps[] | select(.name == "Check out trusted scanner implementation")' "${WORKFLOW}")
}

@test "explicit target checkout uses a repository-scoped token minted only when target-repository is set" {
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Mint scoped token for explicit target repository") | .if' "${WORKFLOW}")" \
    = "inputs.target-repository != ''" ]
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Mint scoped token for explicit target repository") | .with."permission-contents"' "${WORKFLOW}")" = read ]
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Mint scoped token for explicit target repository") | .with."permission-metadata"' "${WORKFLOW}")" = read ]
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Check out untrusted target revision") | .with.token' "${WORKFLOW}")" \
    = "\${{ inputs.target-repository != '' && steps.target-app-token.outputs.token || github.token }}" ]
}

@test "the immutable-target resolver is skipped on direct triggers so it never depends on the trusted base checkout" {
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Resolve immutable scan target") | .if' "${WORKFLOW}")" \
    = "inputs.target-repository != '' || inputs.target-ref != ''" ]
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Check out untrusted target revision") | .with.repository' "${WORKFLOW}")" \
    = "\${{ inputs.target-repository != '' && steps.target.outputs.repository || github.repository }}" ]
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Run trusted repository security pipeline") | .with.repository' "${WORKFLOW}")" \
    = "\${{ inputs.target-repository != '' && steps.target.outputs.repository || github.repository }}" ]
  [ "$(yq eval '.jobs.scan.steps[] | select(.name == "Run trusted repository security pipeline") | .with."commit-sha"' "${WORKFLOW}")" \
    = "\${{ inputs.target-repository != '' && steps.target.outputs.ref || (github.event_name == 'merge_group' && github.event.merge_group.head_sha || github.sha) }}" ]
}

@test "resolve-target.sh rejects a target repository without a full lowercase 40-character commit SHA" {
  local out
  out="${TEST_TEMP}/github-output"
  : > "${out}"
  run env GITHUB_OUTPUT="${out}" TARGET_REPOSITORY=dceoy/segh TARGET_REF=deadbeef \
    "${REPO_ROOT}/.github/actions/repository-security-scan/resolve-target.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'target-ref must be a full lowercase 40-character commit SHA'* ]]
}

@test "resolve-target.sh rejects a target-repository without an owner/name pair" {
  local out
  out="${TEST_TEMP}/github-output"
  : > "${out}"
  run env GITHUB_OUTPUT="${out}" TARGET_REPOSITORY=segh \
    TARGET_REF=0123456789012345678901234567890123456789 \
    "${REPO_ROOT}/.github/actions/repository-security-scan/resolve-target.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'target-repository must be an owner/name pair'* ]]
}

@test "resolve-target.sh rejects a target-ref supplied without a target-repository" {
  local out
  out="${TEST_TEMP}/github-output"
  : > "${out}"
  run env GITHUB_OUTPUT="${out}" TARGET_REF=0123456789012345678901234567890123456789 \
    "${REPO_ROOT}/.github/actions/repository-security-scan/resolve-target.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'target-ref requires target-repository to be set'* ]]
}

@test "resolve-target.sh resolves an explicit immutable target repository and commit SHA" {
  local out
  out="${TEST_TEMP}/github-output"
  : > "${out}"
  run env GITHUB_OUTPUT="${out}" TARGET_REPOSITORY=dceoy/segh \
    TARGET_REF=0123456789012345678901234567890123456789 \
    "${REPO_ROOT}/.github/actions/repository-security-scan/resolve-target.sh"
  [ "${status}" -eq 0 ]
  grep -q '^owner=dceoy$' "${out}"
  grep -q '^name=segh$' "${out}"
  grep -q '^repository=dceoy/segh$' "${out}"
  grep -q '^ref=0123456789012345678901234567890123456789$' "${out}"
}

@test "resolve-target.sh falls back to the caller/event repository and revision when no target is supplied" {
  local out
  out="${TEST_TEMP}/github-output"
  : > "${out}"
  run env GITHUB_OUTPUT="${out}" EVENT_NAME=merge_group EVENT_REPOSITORY=dceoy/gha-for-devops \
    EVENT_SHA=1111111111111111111111111111111111111111 \
    MERGE_GROUP_HEAD_SHA=2222222222222222222222222222222222222222 \
    "${REPO_ROOT}/.github/actions/repository-security-scan/resolve-target.sh"
  [ "${status}" -eq 0 ]
  grep -q '^repository=dceoy/gha-for-devops$' "${out}"
  grep -q '^ref=2222222222222222222222222222222222222222$' "${out}"
}

record_status_fixture() {
  local repository_id="$1"
  local default_branch="$2"

  SECURITY_SCAN_REPOSITORY_ID="${repository_id}" \
    SECURITY_SCAN_DEFAULT_BRANCH="${default_branch}" \
    SECURITY_SCAN_REPOSITORY=dceoy/segh \
    SECURITY_SCAN_COMMIT_SHA=0123456789012345678901234567890123456789 \
    bash "${SCANNER}" status
}

@test "status.json is not written when no repository identity inputs are supplied" {
  prepare_fixture clean
  run_scanners
  record_status_fixture '' ''

  [ ! -e "${GITHUB_WORKSPACE}/security-results/status.json" ]
}

@test "status.json reports pass for a clean scan bound to repository identity" {
  prepare_fixture clean
  run_scanners
  record_status_fixture segh-repository-id main

  [ "$(yq eval --input-format=json '.result' "${GITHUB_WORKSPACE}/security-results/status.json")" = pass ]
  [ "$(yq eval --input-format=json '."repository-id"' "${GITHUB_WORKSPACE}/security-results/status.json")" = segh-repository-id ]
  [ "$(yq eval --input-format=json '.repository' "${GITHUB_WORKSPACE}/security-results/status.json")" = dceoy/segh ]
  [ "$(yq eval --input-format=json '."default-branch"' "${GITHUB_WORKSPACE}/security-results/status.json")" = main ]
  [ "$(yq eval --input-format=json '."commit-sha"' "${GITHUB_WORKSPACE}/security-results/status.json")" = 0123456789012345678901234567890123456789 ]
}

@test "status.json reports findings for a scanner-detected finding" {
  prepare_fixture zizmor-finding
  run_scanners
  record_status_fixture segh-repository-id main

  [ "$(yq eval --input-format=json '.result' "${GITHUB_WORKSPACE}/security-results/status.json")" = findings ]
}

@test "a scanner runtime failure fails its gate and reports error instead of findings" {
  prepare_fixture actionlint-runtime-error
  run_scanners
  run bash "${SCANNER}" enforce
  record_status_fixture segh-repository-id main

  [ "${status}" -ne 0 ]
  [ "$(< "${GITHUB_WORKSPACE}/security-results/actionlint.status")" -eq 2 ]
  [ "$(yq eval --input-format=json '.' "${GITHUB_WORKSPACE}/security-results/actionlint.json")" = '[]' ]
  [ "$(yq eval --input-format=json '.result' "${GITHUB_WORKSPACE}/security-results/status.json")" = error ]
}

@test "status.json reports findings for a preflight-rejected LFS pointer" {
  prepare_fixture lfs-pointer
  run_scanners
  record_status_fixture segh-repository-id main

  [ "$(yq eval --input-format=json '.result' "${GITHUB_WORKSPACE}/security-results/status.json")" = findings ]
}

@test "status.json reports incomplete when required scanner evidence is missing" {
  prepare_fixture clean
  run_scanners
  rm "${GITHUB_WORKSPACE}/security-results/actionlint.json"
  record_status_fixture segh-repository-id main

  [ "$(yq eval --input-format=json '.result' "${GITHUB_WORKSPACE}/security-results/status.json")" = incomplete ]
}

@test "status.json reports error when the target checkout could not be inspected" {
  mkdir -p "${GITHUB_WORKSPACE}/security-results"
  record_status_fixture segh-repository-id main

  [ "$(yq eval --input-format=json '.result' "${GITHUB_WORKSPACE}/security-results/status.json")" = error ]
}

@test "status.json reports error when git ls-files fails during preflight instead of reporting findings" {
  prepare_fixture clean
  rm -rf "${GITHUB_WORKSPACE}/_target/.git"
  bash "${SCANNER}" prepare
  bash "${SCANNER}" preflight
  record_status_fixture segh-repository-id main

  [ "$(< "${GITHUB_WORKSPACE}/security-results/preflight.status")" -eq 1 ]
  [ ! -e "${GITHUB_WORKSPACE}/security-results/rejected-lfs-pointers.txt" ]
  [ ! -e "${GITHUB_WORKSPACE}/security-results/rejected-submodules.txt" ]
  [ "$(yq eval --input-format=json '.result' "${GITHUB_WORKSPACE}/security-results/status.json")" = error ]
}
