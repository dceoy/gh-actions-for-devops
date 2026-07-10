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

update_checksum() {
  local var_name="$1" value="$2"
  [[ "${value}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "::error::failed to resolve a valid SHA-256 for ${var_name}" >&2
    exit 1
  }
  sed -E -i "s/^([[:space:]]*${var_name}:[[:space:]]*)[0-9a-f]{64}[[:space:]]*\$/\1${value}/" "${WORKFLOW_FILE}"
}

update_checksum YQ_SHA256_AMD64 "${yq_sha256_amd64}"
update_checksum YQ_SHA256_ARM64 "${yq_sha256_arm64}"
update_checksum GOMPLATE_SHA256_AMD64 "${gomplate_sha256_amd64}"
update_checksum GOMPLATE_SHA256_ARM64 "${gomplate_sha256_arm64}"

echo "Synced checksums in ${WORKFLOW_FILE} for yq ${yq_version} and gomplate ${gomplate_version}"
