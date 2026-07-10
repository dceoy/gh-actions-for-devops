#!/usr/bin/env bash
#
# Install the pinned, checksum-verified yq and gomplate binaries onto PATH.
#
# Both the update-readme-md CI job (which runs update-readme.sh) and the
# bats-test CI job (whose update-readme.bats suite exercises
# update-readme.sh) need the exact same verified binaries. Rather than
# duplicating the pinned versions/checksums -- which sync-tool-checksums.sh
# and Renovate only know how to keep in sync in one place -- this script
# derives them from the update-readme-md job's env block in
# .github/workflows/ci.yml at run time.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

WORKFLOW_FILE=".github/workflows/ci.yml"

literal_value() {
  local var_name="$1"
  grep -E "^[[:space:]]*${var_name}:[[:space:]]*[^\$[:space:]]" "${WORKFLOW_FILE}" \
    | head -n1 \
    | sed -E "s/^[[:space:]]*${var_name}:[[:space:]]*//"
}

yq_version="$(literal_value YQ_VERSION)"
yq_sha256_amd64="$(literal_value YQ_SHA256_AMD64)"
yq_sha256_arm64="$(literal_value YQ_SHA256_ARM64)"
gomplate_version="$(literal_value GOMPLATE_VERSION)"
gomplate_sha256_amd64="$(literal_value GOMPLATE_SHA256_AMD64)"
gomplate_sha256_arm64="$(literal_value GOMPLATE_SHA256_ARM64)"

[[ "${yq_version}" =~ ^v[0-9]+(\.[0-9]+)*([._+-][A-Za-z0-9]+)*$ ]] || {
  echo "::error::invalid YQ_VERSION read from ${WORKFLOW_FILE}: '${yq_version}'" >&2
  exit 1
}
[[ "${gomplate_version}" =~ ^v[0-9]+(\.[0-9]+)*([._+-][A-Za-z0-9]+)*$ ]] || {
  echo "::error::invalid GOMPLATE_VERSION read from ${WORKFLOW_FILE}: '${gomplate_version}'" >&2
  exit 1
}

arch=amd64
sha_arch=AMD64
if [[ "${RUNNER_ARCH:-}" == "ARM64" ]]; then
  arch=arm64
  sha_arch=ARM64
fi

case "${sha_arch}" in
  AMD64)
    yq_sha256="${yq_sha256_amd64}"
    gomplate_sha256="${gomplate_sha256_amd64}"
    ;;
  ARM64)
    yq_sha256="${yq_sha256_arm64}"
    gomplate_sha256="${gomplate_sha256_arm64}"
    ;;
esac

[[ "${yq_sha256}" =~ ^[0-9a-f]{64}$ ]] || {
  echo "::error::invalid yq SHA-256 read from ${WORKFLOW_FILE}: '${yq_sha256}'" >&2
  exit 1
}
[[ "${gomplate_sha256}" =~ ^[0-9a-f]{64}$ ]] || {
  echo "::error::invalid gomplate SHA-256 read from ${WORKFLOW_FILE}: '${gomplate_sha256}'" >&2
  exit 1
}

mkdir -p "${HOME}/.local/bin"
curl --fail --location --silent --show-error \
  --output "${RUNNER_TEMP}/yq" \
  "https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_linux_${arch}"
echo "${yq_sha256}  ${RUNNER_TEMP}/yq" | sha256sum --check --strict
curl --fail --location --silent --show-error \
  --output "${RUNNER_TEMP}/gomplate" \
  "https://github.com/hairyhenderson/gomplate/releases/download/${gomplate_version}/gomplate_linux-${arch}"
echo "${gomplate_sha256}  ${RUNNER_TEMP}/gomplate" | sha256sum --check --strict
install -m 0755 "${RUNNER_TEMP}/yq" "${HOME}/.local/bin/yq"
install -m 0755 "${RUNNER_TEMP}/gomplate" "${HOME}/.local/bin/gomplate"
echo "${HOME}/.local/bin" >> "${GITHUB_PATH}"
