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
  printf 'Scanner execution was blocked because tracked symlinks could not be removed safely.\n' \
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
  local entry mode file
  local -a rejected=()

  : > "${results_dir}/preflight.log"
  if ! cd "${target_dir}" 2>> "${results_dir}/preflight.log"; then
    printf 'Unable to enter the target checkout.\n' > "${results_dir}/rejected-symlinks.txt"
    printf '1\n' > "${results_dir}/preflight.status"
    return 0
  fi
  if ! git ls-files -z --stage > "${index_file}" 2>> "${results_dir}/preflight.log"; then
    printf 'Unable to enumerate the target checkout before scanning.\n' \
      > "${results_dir}/rejected-symlinks.txt"
    printf '1\n' > "${results_dir}/preflight.status"
    return 0
  fi

  while IFS= read -r -d '' entry; do
    mode=${entry%% *}
    file=${entry#*$'\t'}
    if [[ "${mode}" == '120000' ]]; then
      rejected+=("${file}")
      if ! rm -f -- "${file}" 2>> "${results_dir}/preflight.log"; then
        preflight_status_value=1
      fi
    fi
  done < "${index_file}"
  if ((${#rejected[@]} > 0)); then
    {
      printf 'Removed %d tracked symlink(s) before scanning:\n' "${#rejected[@]}"
      printf '%s\n' "${rejected[@]}"
    } > "${results_dir}/rejected-symlinks.txt"
    printf '::warning::Removed tracked symlinks before scanning the target checkout.\n'
  else
    printf 'No tracked symlinks were present.\n' > "${results_dir}/rejected-symlinks.txt"
  fi
  printf '%s\n' "${preflight_status_value}" > "${results_dir}/preflight.status"
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
  local scanner_status_value render_status_value entry mode file first_line
  local shell_shebang='^#![[:space:]]*(/usr/bin/env[[:space:]]+(-[[:alnum:]-]+[[:space:]]+)*)?(/[^[:space:]]*/)?(busybox[[:space:]]+)?(sh|ash|dash|bash|ksh93|ksh88|ksh|oksh|bats)([[:space:]]|$)'
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
  if ((${#script_files[@]} == 0)); then
    write_skip_evidence shellcheck 'no tracked standalone shell scripts were found.'
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
  summary) publish_summary ;;
  enforce) enforce ;;
  *)
    printf 'usage: %s {prepare|preflight|zizmor|actionlint|shellcheck|checkov|trivy-vulnerability|trivy-secret|summary|enforce}\n' "$0" >&2
    exit 2
    ;;
esac
