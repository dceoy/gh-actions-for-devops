#!/usr/bin/env bash

set -u -o pipefail

readonly trusted_dir="${GITHUB_WORKSPACE}/_trusted"
readonly target_dir="${GITHUB_WORKSPACE}/_target"
readonly results_dir="${GITHUB_WORKSPACE}/security-results"
readonly scanners=(zizmor actionlint shellcheck checkov trivy-vulnerability trivy-secret)

prepare() {
  mkdir -p "${results_dir}"
}

write_skip_evidence() {
  local scanner_name="$1"
  local message="$2"

  printf '[]\n' > "${results_dir}/${scanner_name}.json"
  printf 'Skipped: %s\n' "${message}" > "${results_dir}/${scanner_name}.txt"
  : > "${results_dir}/${scanner_name}.log"
  printf '0\n' > "${results_dir}/${scanner_name}.status"
}

write_preflight_blocked_evidence() {
  local scanner_name="$1"

  printf '{"scanner":"%s","result":"not-run","reason":"preflight failed"}\n' \
    "${scanner_name}" > "${results_dir}/${scanner_name}.json"
  printf 'Not run: target checkout preflight failed.\n' > "${results_dir}/${scanner_name}.txt"
  printf 'Scanner execution was blocked because the target checkout failed trusted preflight validation.\n' \
    > "${results_dir}/${scanner_name}.log"
  printf '125\n' > "${results_dir}/${scanner_name}.status"
}

preflight_succeeded() {
  local scanner_name="$1"
  local preflight_status_file="${results_dir}/preflight.status"
  local preflight_status_value=''

  if [[ -f "${preflight_status_file}" ]]; then
    preflight_status_value="$(< "${preflight_status_file}")"
  fi
  if [[ "${preflight_status_value}" != '0' ]] \
    || [[ ! -f "${results_dir}/tracked-files.index" ]]; then
    write_preflight_blocked_evidence "${scanner_name}"
    return 1
  fi
}

ensure_text_evidence() {
  local scanner_name="$1"
  local scanner_status_value="$2"
  local text_file="${results_dir}/${scanner_name}.txt"

  if [[ ! -s "${text_file}" ]]; then
    if [[ "${scanner_status_value}" == '0' ]]; then
      printf 'Passed: no findings at the enforced threshold.\n' > "${text_file}"
    else
      printf 'The scanner produced no human-readable output; see its log and JSON evidence.\n' \
        > "${text_file}"
    fi
  fi
}

run_preflight() {
  local index_file="${results_dir}/tracked-files.index"
  local preflight_status_value=0
  local preflight_result_value=findings
  local entry mode file lfs_prefix
  local lfs_pointer_pattern=$'^version https://git-lfs.github.com/spec/v1(\n|$)'
  local -a rejected_lfs_pointers=()
  local -a rejected_submodules=()
  local -a rejected_symlinks=()

  : > "${results_dir}/preflight.log"
  if [[ "${SECURITY_SCAN_SETUP_FAILED:-false}" == 'true' ]]; then
    printf 'Target checkout setup failed before preflight could run; see the workflow run log.\n' \
      > "${results_dir}/rejected-symlinks.txt"
    printf '1\n' > "${results_dir}/preflight.status"
    printf 'error\n' > "${results_dir}/preflight.result"
    return 0
  fi
  if ! cd "${target_dir}" 2>> "${results_dir}/preflight.log"; then
    printf 'Unable to enter the target checkout.\n' > "${results_dir}/rejected-symlinks.txt"
    printf '1\n' > "${results_dir}/preflight.status"
    printf 'error\n' > "${results_dir}/preflight.result"
    return 0
  fi
  if ! git ls-files -z --stage > "${index_file}" 2>> "${results_dir}/preflight.log"; then
    printf 'Unable to enumerate the target checkout before scanning.\n' \
      > "${results_dir}/rejected-symlinks.txt"
    printf '1\n' > "${results_dir}/preflight.status"
    printf 'error\n' > "${results_dir}/preflight.result"
    return 0
  fi

  while IFS= read -r -d '' entry; do
    mode=${entry%% *}
    file=${entry#*$'\t'}
    if [[ "${mode}" == '120000' ]]; then
      rejected_symlinks+=("${file}")
      if ! rm -f -- "${file}" 2>> "${results_dir}/preflight.log"; then
        preflight_status_value=1
        preflight_result_value=error
      fi
    elif [[ "${mode}" == '160000' ]]; then
      rejected_submodules+=("${file}")
      preflight_status_value=1
    elif [[ "${mode}" == '100644' || "${mode}" == '100755' ]]; then
      lfs_prefix=''
      IFS= read -r -N 200 lfs_prefix < "${file}"
      if [[ "${lfs_prefix}" =~ ${lfs_pointer_pattern} ]]; then
        rejected_lfs_pointers+=("${file}")
        preflight_status_value=1
      fi
    fi
  done < "${index_file}"
  if ((${#rejected_symlinks[@]} > 0)); then
    {
      printf 'Removed %d tracked symlink(s) before scanning:\n' "${#rejected_symlinks[@]}"
      printf '%s\n' "${rejected_symlinks[@]}"
    } > "${results_dir}/rejected-symlinks.txt"
    printf '::warning::Removed tracked symlinks before scanning the target checkout.\n'
  else
    printf 'No tracked symlinks were present.\n' > "${results_dir}/rejected-symlinks.txt"
  fi
  if ((${#rejected_lfs_pointers[@]} > 0)); then
    {
      printf 'Rejected %d tracked Git LFS pointer(s); materialize their content before scanning:\n' \
        "${#rejected_lfs_pointers[@]}"
      printf '%s\n' "${rejected_lfs_pointers[@]}"
    } > "${results_dir}/rejected-lfs-pointers.txt"
    printf '::error::Tracked Git LFS pointer content is not materialized in the target checkout.\n'
  else
    printf 'No tracked Git LFS pointers were present.\n' \
      > "${results_dir}/rejected-lfs-pointers.txt"
  fi
  if ((${#rejected_submodules[@]} > 0)); then
    {
      printf 'Rejected %d tracked submodule gitlink(s); materialize their content before scanning:\n' \
        "${#rejected_submodules[@]}"
      printf '%s\n' "${rejected_submodules[@]}"
    } > "${results_dir}/rejected-submodules.txt"
    printf '::error::Tracked submodule content is not materialized in the target checkout.\n'
  else
    printf 'No tracked submodule gitlinks were present.\n' \
      > "${results_dir}/rejected-submodules.txt"
  fi
  printf '%s\n' "${preflight_status_value}" > "${results_dir}/preflight.status"
  if ((preflight_status_value != 0)); then
    printf '%s\n' "${preflight_result_value}" > "${results_dir}/preflight.result"
  fi
}

collect_regular_files() {
  local -n output_files=$1
  local selection="$2"
  local entry mode file

  output_files=()
  while IFS= read -r -d '' entry; do
    mode=${entry%% *}
    file=${entry#*$'\t'}
    if [[ "${mode}" != '100644' && "${mode}" != '100755' ]]; then
      continue
    fi
    case "${selection}" in
      workflows)
        [[ "${file}" =~ ^\.github/workflows/[^/]+\.ya?ml$ ]] && output_files+=("${file}")
        ;;
      github-actions)
        if [[ "${file}" =~ ^\.github/workflows/[^/]+\.ya?ml$ ]] \
          || [[ "${file}" =~ (^|.*/)action\.ya?ml$ ]]; then
          output_files+=("${file}")
        fi
        ;;
      *) return 2 ;;
    esac
  done < "${results_dir}/tracked-files.index"
}

write_shellcheck_directive_failure() {
  local scanner_name="$1"
  local directive_report="$2"

  printf '{"scanner":"%s","result":"policy-violation","reason":"target-owned ShellCheck directives"}\n' \
    "${scanner_name}" > "${results_dir}/${scanner_name}.json"
  {
    printf 'Failed: target-owned ShellCheck directives are not allowed; exclusions belong in the trusted policy.\n'
    sed 's/^/  /' "${directive_report}"
  } > "${results_dir}/${scanner_name}.txt"
  printf '1\n' > "${results_dir}/${scanner_name}.status"
}

reject_workflow_shellcheck_directives() {
  local scanner_name="$1"
  shift
  local file match
  local directive_pattern='^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]+[[:alpha:]-]+='
  local directive_report="${results_dir}/${scanner_name}.shellcheck-directives"
  local dynamic_shells="${results_dir}/${scanner_name}.dynamic-shells"
  local run_blocks="${results_dir}/${scanner_name}.run-blocks"
  local matches="${results_dir}/${scanner_name}.shellcheck-matches"
  local expression_marker='$'

  : > "${directive_report}"
  : > "${results_dir}/${scanner_name}.log"
  for file in "$@"; do
    if ! yq eval --output-format=json --unwrapScalar=false \
      "[.defaults.run.shell, .jobs[]?.defaults.run.shell, (.jobs[]?.steps[]? | select(has(\"run\")) | .shell)] | .[] | select((. // \"\") | contains(\"${expression_marker}{{\"))" \
      "${file}" > "${dynamic_shells}" 2>> "${results_dir}/${scanner_name}.log"; then
      printf '{"scanner":"%s","result":"not-run","reason":"unable to inspect workflow shell values"}\n' \
        "${scanner_name}" > "${results_dir}/${scanner_name}.json"
      printf 'Failed: unable to inspect workflow shell values.\n' \
        > "${results_dir}/${scanner_name}.txt"
      printf '1\n' > "${results_dir}/${scanner_name}.status"
      rm -f -- "${directive_report}" "${dynamic_shells}" "${run_blocks}" "${matches}"
      return 0
    fi
    if [[ -s "${dynamic_shells}" ]]; then
      printf '{"scanner":"%s","result":"policy-violation","reason":"expression-valued workflow shell"}\n' \
        "${scanner_name}" > "${results_dir}/${scanner_name}.json"
      printf 'Failed: expression-valued workflow shells are not allowed because their interpreter cannot be verified.\n' \
        > "${results_dir}/${scanner_name}.txt"
      printf 'Rejected expression-valued workflow shell in %s.\n' "${file}" \
        >> "${results_dir}/${scanner_name}.log"
      printf '1\n' > "${results_dir}/${scanner_name}.status"
      rm -f -- "${directive_report}" "${dynamic_shells}" "${run_blocks}" "${matches}"
      return 0
    fi
    if ! yq eval '.jobs[]?.steps[]? | select(has("run")) | .run' "${file}" \
      > "${run_blocks}" 2>> "${results_dir}/${scanner_name}.log"; then
      printf '{"scanner":"%s","result":"not-run","reason":"unable to inspect workflow shell blocks"}\n' \
        "${scanner_name}" > "${results_dir}/${scanner_name}.json"
      printf 'Failed: unable to inspect workflow shell blocks for target-owned ShellCheck directives.\n' \
        > "${results_dir}/${scanner_name}.txt"
      printf '1\n' > "${results_dir}/${scanner_name}.status"
      rm -f -- "${directive_report}" "${dynamic_shells}" "${run_blocks}" "${matches}"
      return 0
    fi
    if LC_ALL=C grep -nE "${directive_pattern}" "${run_blocks}" > "${matches}"; then
      while IFS= read -r match; do
        printf '%s:%s\n' "${file}" "${match}" >> "${directive_report}"
      done < "${matches}"
    fi
  done
  rm -f -- "${dynamic_shells}" "${run_blocks}" "${matches}"
  if [[ -s "${directive_report}" ]]; then
    write_shellcheck_directive_failure "${scanner_name}" "${directive_report}"
    rm -f -- "${directive_report}"
    return 0
  fi
  rm -f -- "${directive_report}" "${results_dir}/${scanner_name}.log"
  return 1
}

reject_script_shellcheck_directives() {
  local scanner_name="$1"
  shift
  local grep_status
  local directive_pattern='^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]+[[:alpha:]-]+='
  local directive_report="${results_dir}/${scanner_name}.shellcheck-directives"

  : > "${results_dir}/${scanner_name}.log"
  LC_ALL=C grep -nHE "${directive_pattern}" -- "$@" \
    > "${directive_report}" 2>> "${results_dir}/${scanner_name}.log"
  grep_status=$?
  if ((grep_status == 0)); then
    write_shellcheck_directive_failure "${scanner_name}" "${directive_report}"
    rm -f -- "${directive_report}"
    return 0
  fi
  if ((grep_status != 1)); then
    printf '{"scanner":"%s","result":"not-run","reason":"unable to inspect shell scripts"}\n' \
      "${scanner_name}" > "${results_dir}/${scanner_name}.json"
    printf 'Failed: unable to inspect shell scripts for target-owned ShellCheck directives.\n' \
      > "${results_dir}/${scanner_name}.txt"
    printf '1\n' > "${results_dir}/${scanner_name}.status"
    rm -f -- "${directive_report}"
    return 0
  fi
  rm -f -- "${directive_report}" "${results_dir}/${scanner_name}.log"
  return 1
}

extract_composite_action_shell_blocks() {
  local output_name=$1
  shift
  local -n composite_output_ref=${output_name}
  local action_file block_json block_index decode_status extracted_file
  local blocks_jsonl="${results_dir}/shellcheck-composite-blocks.jsonl"
  local extraction_dir="${results_dir}/shellcheck-composite"
  local expression_marker='$'
  local shell_pattern='(^|[[:space:]/])(sh|ash|dash|bash|ksh93|ksh88|ksh|oksh|bats)([[:space:]]|$)'

  composite_output_ref=()
  for action_file in "$@"; do
    if ! yq eval --output-format=json --unwrapScalar=false \
      "select(.runs.using == \"composite\") | .runs.steps[]? | select(has(\"run\")) | select((.shell // \"\") | contains(\"${expression_marker}{{\")) | .shell" \
      "${action_file}" > "${blocks_jsonl}" 2>> "${results_dir}/shellcheck.log"; then
      rm -f -- "${blocks_jsonl}"
      rm -rf -- "${extraction_dir}"
      return 1
    fi
    if [[ -s "${blocks_jsonl}" ]]; then
      printf 'Rejected expression-valued composite shell in %s.\n' "${action_file}" \
        >> "${results_dir}/shellcheck.log"
      rm -f -- "${blocks_jsonl}"
      rm -rf -- "${extraction_dir}"
      return 2
    fi
    if ! yq eval --output-format=json --unwrapScalar=false \
      "select(.runs.using == \"composite\") | .runs.steps[]? | select(has(\"run\")) | select(.shell | test(\"${shell_pattern}\")) | .run" \
      "${action_file}" > "${blocks_jsonl}" 2>> "${results_dir}/shellcheck.log"; then
      rm -f -- "${blocks_jsonl}"
      rm -rf -- "${extraction_dir}"
      return 1
    fi

    block_index=0
    decode_status=0
    while IFS= read -r block_json; do
      extracted_file="${extraction_dir}/${action_file}/step-${block_index}.sh"
      mkdir -p "$(dirname "${extracted_file}")"
      if ! printf '%s\n' "${block_json}" \
        | yq eval --input-format=json --unwrapScalar '.' - \
          > "${extracted_file}" 2>> "${results_dir}/shellcheck.log"; then
        decode_status=1
        break
      fi
      composite_output_ref+=("${extracted_file}")
      ((block_index += 1))
    done < "${blocks_jsonl}"
    if ((decode_status != 0)); then
      rm -f -- "${blocks_jsonl}"
      rm -rf -- "${extraction_dir}"
      return 1
    fi
  done
  rm -f -- "${blocks_jsonl}"
}

run_zizmor() {
  local scanner_status_value render_status_value
  local -a workflow_files=()

  preflight_succeeded zizmor || return 0
  cd "${target_dir}" || return 0
  collect_regular_files workflow_files github-actions
  if ((${#workflow_files[@]} == 0)); then
    write_skip_evidence zizmor 'no tracked GitHub Actions workflows or actions were found.'
    return 0
  fi

  : > "${results_dir}/zizmor.log"
  zizmor \
    --offline \
    --no-config \
    --no-ignores \
    --strict-collection \
    --persona regular \
    --min-severity medium \
    --min-confidence high \
    --format json \
    "${workflow_files[@]}" \
    > "${results_dir}/zizmor.json" \
    2>> "${results_dir}/zizmor.log"
  scanner_status_value=$?
  zizmor \
    --offline \
    --no-config \
    --no-ignores \
    --strict-collection \
    --persona regular \
    --min-severity medium \
    --min-confidence high \
    --no-exit-codes \
    --format plain \
    --color never \
    --render-links never \
    --show-audit-urls always \
    "${workflow_files[@]}" \
    > "${results_dir}/zizmor.txt" \
    2>> "${results_dir}/zizmor.log"
  render_status_value=$?
  if ((scanner_status_value == 0 && render_status_value != 0)); then
    scanner_status_value=${render_status_value}
  fi
  ensure_text_evidence zizmor "${scanner_status_value}"
  printf '%s\n' "${scanner_status_value}" > "${results_dir}/zizmor.status"
}

run_actionlint() {
  local scanner_status_value render_status_value
  local json_lines="${results_dir}/actionlint.jsonl"
  local -a workflow_files=()

  preflight_succeeded actionlint || return 0
  cd "${target_dir}" || return 0
  collect_regular_files workflow_files workflows
  if ((${#workflow_files[@]} == 0)); then
    write_skip_evidence actionlint 'no tracked GitHub Actions workflow files were found.'
    return 0
  fi
  if reject_workflow_shellcheck_directives actionlint "${workflow_files[@]}"; then
    return 0
  fi

  : > "${results_dir}/actionlint.log"
  SHELLCHECK_OPTS="--rcfile=${trusted_dir}/.github/security/repository-security/shellcheckrc" \
    actionlint \
    --no-color \
    --config-file "${trusted_dir}/.github/security/repository-security/actionlint.yaml" \
    --shellcheck shellcheck \
    --format '{{json .}}' \
    "${workflow_files[@]}" \
    > "${json_lines}" \
    2>> "${results_dir}/actionlint.log"
  scanner_status_value=$?
  if [[ -s "${json_lines}" ]]; then
    if ! yq eval-all --input-format=json --output-format=json '[.]' "${json_lines}" \
      > "${results_dir}/actionlint.json" 2>> "${results_dir}/actionlint.log"; then
      printf '::error::actionlint produced JSON Lines output that could not be converted to a JSON array; see actionlint.log.\n'
      printf '[]\n' > "${results_dir}/actionlint.json"
      scanner_status_value=1
    fi
  else
    printf '[]\n' > "${results_dir}/actionlint.json"
  fi
  rm -f -- "${json_lines}"

  SHELLCHECK_OPTS="--rcfile=${trusted_dir}/.github/security/repository-security/shellcheckrc" \
    actionlint \
    --no-color \
    --config-file "${trusted_dir}/.github/security/repository-security/actionlint.yaml" \
    --shellcheck shellcheck \
    "${workflow_files[@]}" \
    > "${results_dir}/actionlint.txt" \
    2>> "${results_dir}/actionlint.log"
  render_status_value=$?
  if ((scanner_status_value == 0 && render_status_value != 0)); then
    scanner_status_value=${render_status_value}
  fi
  ensure_text_evidence actionlint "${scanner_status_value}"
  printf '%s\n' "${scanner_status_value}" > "${results_dir}/actionlint.status"
}

run_shellcheck() {
  local scanner_status_value render_status_value entry mode file first_line extraction_status
  local shell_shebang='^#![[:space:]]*(/usr/bin/env[[:space:]]+([^[:space:]]+[[:space:]]+)*)?(/[^[:space:]]*/)?(busybox[[:space:]]+)?(sh|ash|dash|bash|ksh93|ksh88|ksh|oksh|bats)([[:space:]]|$)'
  local composite_shell_dir="${results_dir}/shellcheck-composite"
  local -a action_files=()
  local -a composite_shell_files=()
  local -a script_files=()
  local -a unreadable_files=()

  preflight_succeeded shellcheck || return 0
  cd "${target_dir}" || return 0
  while IFS= read -r -d '' entry; do
    mode=${entry%% *}
    file=${entry#*$'\t'}
    if [[ "${mode}" != '100644' && "${mode}" != '100755' ]]; then
      continue
    fi
    if [[ "${file}" =~ (^|.*/)action\.ya?ml$ ]]; then
      action_files+=("${file}")
    fi
    if [[ "${file}" == *.sh || "${file}" == *.bash || "${file}" == *.bats ]]; then
      script_files+=("${file}")
      continue
    fi
    if [[ ! -r "${file}" ]]; then
      printf '::error::Unable to read %s while probing for a shell shebang.\n' "${file}"
      unreadable_files+=("${file}")
      continue
    fi
    first_line=''
    IFS= read -r -n 256 first_line < "${file}"
    if [[ "${first_line}" =~ ${shell_shebang} ]]; then
      script_files+=("${file}")
    fi
  done < "${results_dir}/tracked-files.index"
  if ((${#unreadable_files[@]} > 0)); then
    : > "${results_dir}/shellcheck.log"
    printf '[]\n' > "${results_dir}/shellcheck.json"
    {
      printf 'Failed: unable to read %d tracked file(s) while probing for shell shebangs:\n' \
        "${#unreadable_files[@]}"
      printf '%s\n' "${unreadable_files[@]}"
    } > "${results_dir}/shellcheck.txt"
    printf '1\n' > "${results_dir}/shellcheck.status"
    return 0
  fi

  : > "${results_dir}/shellcheck.log"
  extract_composite_action_shell_blocks composite_shell_files "${action_files[@]}"
  extraction_status=$?
  if ((extraction_status == 2)); then
    printf '{"scanner":"shellcheck","result":"policy-violation","reason":"expression-valued composite shell"}\n' \
      > "${results_dir}/shellcheck.json"
    printf 'Failed: expression-valued composite shells are not allowed because their interpreter cannot be verified.\n' \
      > "${results_dir}/shellcheck.txt"
    printf '1\n' > "${results_dir}/shellcheck.status"
    return 0
  fi
  if ((extraction_status != 0)); then
    printf '{"scanner":"shellcheck","result":"not-run","reason":"unable to inspect composite action shell blocks"}\n' \
      > "${results_dir}/shellcheck.json"
    printf 'Failed: unable to inspect composite action shell blocks.\n' \
      > "${results_dir}/shellcheck.txt"
    printf '1\n' > "${results_dir}/shellcheck.status"
    return 0
  fi
  script_files+=("${composite_shell_files[@]}")
  if ((${#script_files[@]} == 0)); then
    write_skip_evidence shellcheck 'no tracked standalone shell scripts or composite action shell blocks were found.'
    return 0
  fi
  if reject_script_shellcheck_directives shellcheck "${script_files[@]}"; then
    rm -rf -- "${composite_shell_dir}"
    return 0
  fi

  : > "${results_dir}/shellcheck.log"
  shellcheck \
    --color=never \
    --format=json1 \
    --rcfile "${trusted_dir}/.github/security/repository-security/shellcheckrc" \
    --severity=style \
    -- \
    "${script_files[@]}" \
    > "${results_dir}/shellcheck.json" \
    2>> "${results_dir}/shellcheck.log"
  scanner_status_value=$?
  shellcheck \
    --color=never \
    --format=gcc \
    --rcfile "${trusted_dir}/.github/security/repository-security/shellcheckrc" \
    --severity=style \
    -- \
    "${script_files[@]}" \
    > "${results_dir}/shellcheck.txt" \
    2>> "${results_dir}/shellcheck.log"
  render_status_value=$?
  rm -rf -- "${composite_shell_dir}"
  if ((scanner_status_value == 0 && render_status_value != 0)); then
    scanner_status_value=${render_status_value}
  fi
  ensure_text_evidence shellcheck "${scanner_status_value}"
  printf '%s\n' "${scanner_status_value}" > "${results_dir}/shellcheck.status"
}

run_checkov() {
  local scanner_status_value suppressed_check_count

  preflight_succeeded checkov || return 0
  cd "${target_dir}" || return 0
  : > "${results_dir}/checkov.log"
  checkov \
    --directory . \
    --config-file "${trusted_dir}/.github/security/repository-security/checkov.yaml" \
    --skip-download \
    --output json \
    --output cli \
    --output-file-path "${results_dir}/checkov.json,${results_dir}/checkov.txt" \
    >> "${results_dir}/checkov.log" 2>&1
  scanner_status_value=$?
  if ((scanner_status_value == 0)) && [[ ! -s "${results_dir}/checkov.txt" ]]; then
    printf 'Skipped: no supported infrastructure-as-code resources were found.\n' \
      > "${results_dir}/checkov.txt"
  fi

  # checkov has no flag to disable inline `#checkov:skip=` suppressions. The
  # trusted config's skip-check list is always empty, so any entry under
  # results.skipped_checks can only originate from a target-owned inline
  # suppression comment; fail the gate closed on that, mirroring --no-ignores
  # for zizmor.
  suppressed_check_count=0
  if [[ -s "${results_dir}/checkov.json" ]]; then
    suppressed_check_count="$(
      yq eval '[.. | select(has("skipped_checks")) | .skipped_checks[]] | length' \
        --input-format=json "${results_dir}/checkov.json" 2> /dev/null
    )"
    [[ "${suppressed_check_count}" =~ ^[0-9]+$ ]] || suppressed_check_count=0
  fi
  if ((suppressed_check_count > 0)); then
    printf '::error::Checkov reported %d check(s) skipped via inline suppression comments; this trusted gate does not honor target-owned suppressions.\n' \
      "${suppressed_check_count}" >> "${results_dir}/checkov.log"
    printf 'Failed: %d check(s) were skipped via inline suppression comments (e.g. "checkov:skip="), which this trusted gate does not honor.\n' \
      "${suppressed_check_count}" >> "${results_dir}/checkov.txt"
    scanner_status_value=1
  fi

  ensure_text_evidence checkov "${scanner_status_value}"
  printf '%s\n' "${scanner_status_value}" > "${results_dir}/checkov.status"
}

run_trivy() {
  local scanner_name="$1"
  local scanner_kind="$2"
  local severity="$3"
  local scanner_status_value convert_status_value
  local -a secret_config_args=()

  preflight_succeeded "${scanner_name}" || return 0
  cd "${target_dir}" || return 0
  if [[ "${scanner_kind}" == 'secret' ]]; then
    secret_config_args=(--secret-config "${trusted_dir}/.github/security/repository-security/trivy-secret.yaml")
  fi

  : > "${results_dir}/${scanner_name}.log"
  trivy filesystem \
    --config /dev/null \
    --ignorefile /dev/null \
    "${secret_config_args[@]}" \
    --scanners "${scanner_kind}" \
    --severity "${severity}" \
    --exit-code 1 \
    --format json \
    --output "${results_dir}/${scanner_name}.json" \
    --skip-dirs .git \
    --skip-version-check \
    . \
    2>> "${results_dir}/${scanner_name}.log"
  scanner_status_value=$?
  trivy convert \
    --config /dev/null \
    --scanners "${scanner_kind}" \
    --format table \
    --output "${results_dir}/${scanner_name}.txt" \
    "${results_dir}/${scanner_name}.json" \
    2>> "${results_dir}/${scanner_name}.log"
  convert_status_value=$?
  if ((scanner_status_value == 0 && convert_status_value != 0)); then
    scanner_status_value=${convert_status_value}
  fi
  ensure_text_evidence "${scanner_name}" "${scanner_status_value}"
  printf '%s\n' "${scanner_status_value}" > "${results_dir}/${scanner_name}.status"
}

classify_result() {
  local preflight_status_value='' scanner_name scanner_status_value
  local has_incomplete=0 has_findings=0 has_error=0

  if [[ ! -f "${results_dir}/preflight.status" ]]; then
    printf 'error'
    return 0
  fi
  preflight_status_value="$(< "${results_dir}/preflight.status")"
  if [[ "${preflight_status_value}" != '0' ]]; then
    if [[ -f "${results_dir}/preflight.result" ]]; then
      cat -- "${results_dir}/preflight.result"
    else
      printf 'error'
    fi
    return 0
  fi

  for scanner_name in "${scanners[@]}"; do
    local scanner_status_file="${results_dir}/${scanner_name}.status"
    local scanner_json_file="${results_dir}/${scanner_name}.json"

    if [[ ! -f "${scanner_status_file}" ]]; then
      has_incomplete=1
      continue
    fi
    scanner_status_value="$(< "${scanner_status_file}")"
    if [[ ! "${scanner_status_value}" =~ ^[0-9]+$ ]]; then
      has_incomplete=1
      continue
    fi
    if [[ ! -s "${scanner_json_file}" ]] \
      || ! yq eval --input-format=json '.' "${scanner_json_file}" > /dev/null 2>&1; then
      has_incomplete=1
      continue
    fi
    if [[ ! -s "${results_dir}/${scanner_name}.txt" ]] \
      || [[ ! -f "${results_dir}/${scanner_name}.log" ]]; then
      has_incomplete=1
      continue
    fi
    if ((scanner_status_value == 0)); then
      continue
    fi
    if yq eval --exit-status --input-format=json '.result == "not-run"' "${scanner_json_file}" \
      > /dev/null 2>&1; then
      has_incomplete=1
    elif ((scanner_status_value > 1)); then
      # A status of 1 is every scanner's own convention for "policy findings
      # at the enforced threshold". Anything higher (and not already claimed
      # as not-run above) means the tool itself failed to complete its scan
      # (e.g. a usage error or crash), which is not a policy finding.
      has_error=1
    else
      has_findings=1
    fi
  done

  if ((has_error == 1)); then
    printf 'error'
  elif ((has_incomplete == 1)); then
    printf 'incomplete'
  elif ((has_findings == 1)); then
    printf 'findings'
  else
    printf 'pass'
  fi
}

json_escape() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

record_status() {
  local repository_id="${SECURITY_SCAN_REPOSITORY_ID:-}"
  local default_branch="${SECURITY_SCAN_DEFAULT_BRANCH:-}"
  local repository="${SECURITY_SCAN_REPOSITORY:-}"
  local commit_sha="${SECURITY_SCAN_COMMIT_SHA:-}"
  local result

  if [[ -z "${repository_id}" && -z "${default_branch}" ]]; then
    return 0
  fi
  # Written without yq so a failed scanner install still uploads status
  # evidence instead of silently dropping this always-run step's output.
  result="$(classify_result)"
  printf '{"result":"%s","repository-id":"%s","repository":"%s","default-branch":"%s","commit-sha":"%s"}\n' \
    "$(json_escape "${result}")" \
    "$(json_escape "${repository_id}")" \
    "$(json_escape "${repository}")" \
    "$(json_escape "${default_branch}")" \
    "$(json_escape "${commit_sha}")" \
    > "${results_dir}/status.json"
}

publish_summary() {
  local scanner_name text_file

  for scanner_name in "${scanners[@]}"; do
    text_file="${results_dir}/${scanner_name}.txt"
    {
      printf '## %s\n\n' "${scanner_name}"
      if [[ -f "${text_file}" ]]; then
        LC_ALL=C head -c 16384 "${text_file}" | sed -n '1,120{s/^/    /;p;}'
        printf '\n\n'
      else
        printf 'No human-readable report was produced. See the retained artifact.\n\n'
      fi
    } >> "${GITHUB_STEP_SUMMARY}"
  done
}

enforce() {
  local aggregate_status=0
  local scanner_name scanner_status_file scanner_status_value evidence_file
  local preflight_status_file="${results_dir}/preflight.status"

  if [[ ! -f "${preflight_status_file}" ]] || [[ "$(< "${preflight_status_file}")" != '0' ]]; then
    printf '::error::Target checkout preflight did not complete successfully.\n'
    aggregate_status=1
  fi

  for scanner_name in "${scanners[@]}"; do
    scanner_status_file="${results_dir}/${scanner_name}.status"
    if [[ ! -f "${scanner_status_file}" ]]; then
      printf '::error::%s did not produce a status file.\n' "${scanner_name}"
      aggregate_status=1
    else
      scanner_status_value="$(< "${scanner_status_file}")"
      if [[ ! "${scanner_status_value}" =~ ^[0-9]+$ ]] || ((scanner_status_value != 0)); then
        printf '::error::%s gate failed with status %s.\n' "${scanner_name}" "${scanner_status_value}"
        aggregate_status=1
      fi
    fi

    for evidence_file in \
      "${results_dir}/${scanner_name}.json" \
      "${results_dir}/${scanner_name}.txt" \
      "${results_dir}/${scanner_name}.log"; do
      if [[ ! -f "${evidence_file}" ]]; then
        printf '::error::%s did not produce required evidence %s.\n' \
          "${scanner_name}" "$(basename "${evidence_file}")"
        aggregate_status=1
      fi
    done
    if [[ ! -s "${results_dir}/${scanner_name}.json" ]] \
      || ! yq eval --input-format=json '.' "${results_dir}/${scanner_name}.json" > /dev/null 2>&1; then
      printf '::error::%s did not produce valid JSON evidence.\n' "${scanner_name}"
      aggregate_status=1
    fi
    if [[ ! -s "${results_dir}/${scanner_name}.txt" ]]; then
      printf '::error::%s did not produce non-empty text evidence.\n' "${scanner_name}"
      aggregate_status=1
    fi
  done
  return "${aggregate_status}"
}

case "${1:-}" in
  prepare) prepare ;;
  preflight) run_preflight ;;
  zizmor) run_zizmor ;;
  actionlint) run_actionlint ;;
  shellcheck) run_shellcheck ;;
  checkov) run_checkov ;;
  trivy-vulnerability) run_trivy trivy-vulnerability vuln HIGH,CRITICAL ;;
  trivy-secret) run_trivy trivy-secret secret UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL ;;
  status) record_status ;;
  summary) publish_summary ;;
  enforce) enforce ;;
  *)
    printf 'usage: %s {prepare|preflight|zizmor|actionlint|shellcheck|checkov|trivy-vulnerability|trivy-secret|status|summary|enforce}\n' "$0" >&2
    exit 2
    ;;
esac
