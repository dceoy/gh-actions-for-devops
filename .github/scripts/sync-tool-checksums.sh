#!/usr/bin/env bash
#
# Fetch the official published SHA-256 checksums for the pinned yq and
# gomplate versions declared in .github/workflows/ci.yml, and rewrite the
# matching *_SHA256_AMD64 / *_SHA256_ARM64 env vars in place so a version
# bump can never leave a stale checksum behind.
#
# Run manually after bumping YQ_VERSION or GOMPLATE_VERSION by hand, or
# automatically as a Renovate postUpgradeTask (see .github/renovate.json)
# right after the regex managers bump those versions.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

WORKFLOW_FILE=".github/workflows/ci.yml"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Read the literal (non-templated) value assigned to a `NAME: value` line,
# ignoring `NAME: ${{ ... }}` references elsewhere in the same file.
literal_value() {
  local var_name="$1"
  grep -E "^[[:space:]]*${var_name}:[[:space:]]*[^\$[:space:]]" "${WORKFLOW_FILE}" \
    | head -n1 \
    | sed -E "s/^[[:space:]]*${var_name}:[[:space:]]*//"
}

fetch() {
  curl --fail --location --silent --show-error --output "$2" "$1"
}

yq_version="$(literal_value YQ_VERSION)"
gomplate_version="$(literal_value GOMPLATE_VERSION)"

[[ "${yq_version}" =~ ^v[0-9]+(\.[0-9]+)*([._+-][A-Za-z0-9]+)*$ ]] || {
  echo "::error::invalid YQ_VERSION read from ${WORKFLOW_FILE}: '${yq_version}'" >&2
  exit 1
}
[[ "${gomplate_version}" =~ ^v[0-9]+(\.[0-9]+)*([._+-][A-Za-z0-9]+)*$ ]] || {
  echo "::error::invalid GOMPLATE_VERSION read from ${WORKFLOW_FILE}: '${gomplate_version}'" >&2
  exit 1
}

# yq publishes one "checksums" file covering many hash algorithms per
# release, with the column order randomized each time and recorded in
# "checksums_hashes_order" -- so the SHA-256 column index must be looked
# up per release rather than hard-coded.
fetch \
  "https://github.com/mikefarah/yq/releases/download/${yq_version}/checksums_hashes_order" \
  "${WORK_DIR}/yq_checksums_hashes_order"
fetch \
  "https://github.com/mikefarah/yq/releases/download/${yq_version}/checksums" \
  "${WORK_DIR}/yq_checksums"

sha256_order_line="$(grep -n -x 'SHA-256' "${WORK_DIR}/yq_checksums_hashes_order")"
sha256_column=$(( "${sha256_order_line%%:*}" + 1 ))

yq_sha256_for() {
  awk -v col="${sha256_column}" -v want="$1" '$1 == want { print $col }' "${WORK_DIR}/yq_checksums"
}

yq_sha256_amd64="$(yq_sha256_for yq_linux_amd64)"
yq_sha256_arm64="$(yq_sha256_for yq_linux_arm64)"

# gomplate publishes a plain `sha256sum`-format checksums file per release.
fetch \
  "https://github.com/hairyhenderson/gomplate/releases/download/${gomplate_version}/checksums-${gomplate_version}_sha256.txt" \
  "${WORK_DIR}/gomplate_checksums"

gomplate_sha256_for() {
  awk -v want="bin/$1" '$2 == want { print $1 }' "${WORK_DIR}/gomplate_checksums"
}

gomplate_sha256_amd64="$(gomplate_sha256_for gomplate_linux-amd64)"
gomplate_sha256_arm64="$(gomplate_sha256_for gomplate_linux-arm64)"

# Matches a `NAME: <value>` assignment whose value is a bare, single-quoted,
# or double-quoted 64-char lowercase hex digest, optionally followed by an
# inline `# ...` comment. Capture groups isolate the parts around the digest
# (prefix, opening quote, closing quote/trailing comment) so a replacement
# can preserve the surrounding quoting/comment style verbatim.
checksum_line_pattern() {
  local var_name="$1"
  printf '^([[:space:]]*%s:[[:space:]]*)(['"'"'"]?)[0-9a-f]{64}(['"'"'"]?[[:space:]]*(#.*)?)$' "${var_name}"
}

# Same shape as checksum_line_pattern, but captures the digest itself
# (instead of the surrounding text) so the assigned value can be read back.
checksum_value_pattern() {
  local var_name="$1"
  printf '^[[:space:]]*%s:[[:space:]]*['"'"'"]?([0-9a-f]{64})['"'"'"]?[[:space:]]*(#.*)?$' "${var_name}"
}

# Rewrites the NAME: assignment in `file` to `value`, requiring that exactly
# one line currently matches the expected checksum-assignment shape and that
# the rewritten line reads back as exactly `value` afterward. Fails closed
# (leaving `file` untouched) on zero matches, duplicate matches, an
# unresolvable `value`, or a post-write mismatch.
update_checksum() {
  local var_name="$1" value="$2" file="$3"
  [[ "${value}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "::error::failed to resolve a valid SHA-256 for ${var_name}" >&2
    return 1
  }

  local line_pattern
  line_pattern="$(checksum_line_pattern "${var_name}")"

  local n_matches
  n_matches="$(grep -c -E "${line_pattern}" "${file}" || true)"
  if [[ "${n_matches}" -ne 1 ]]; then
    echo "::error::expected exactly one ${var_name} checksum assignment in ${file}, found ${n_matches}" >&2
    return 1
  fi

  sed -E -i "s/${line_pattern}/\\1\\2${value}\\3/" "${file}"

  local value_pattern new_value
  value_pattern="$(checksum_value_pattern "${var_name}")"
  new_value="$(sed -E -n "s/${value_pattern}/\\1/p" "${file}")"
  if [[ "${new_value}" != "${value}" ]]; then
    echo "::error::failed to verify updated ${var_name} in ${file}: expected ${value}, found '${new_value}'" >&2
    return 1
  fi
}

TMP_WORKFLOW_FILE="$(mktemp "$(dirname "${WORKFLOW_FILE}")/.$(basename "${WORKFLOW_FILE}").XXXXXX")"
trap 'rm -rf "${WORK_DIR}" "${TMP_WORKFLOW_FILE}"' EXIT
cp "${WORKFLOW_FILE}" "${TMP_WORKFLOW_FILE}"

update_checksum YQ_SHA256_AMD64 "${yq_sha256_amd64}" "${TMP_WORKFLOW_FILE}"
update_checksum YQ_SHA256_ARM64 "${yq_sha256_arm64}" "${TMP_WORKFLOW_FILE}"
update_checksum GOMPLATE_SHA256_AMD64 "${gomplate_sha256_amd64}" "${TMP_WORKFLOW_FILE}"
update_checksum GOMPLATE_SHA256_ARM64 "${gomplate_sha256_arm64}" "${TMP_WORKFLOW_FILE}"

mv "${TMP_WORKFLOW_FILE}" "${WORKFLOW_FILE}"

echo "Synced checksums in ${WORKFLOW_FILE} for yq ${yq_version} and gomplate ${gomplate_version}"
