#!/usr/bin/env bash
#
# Install the yq and gomplate CLI commands at the versions pinned in
# .github/tools/go.mod, using the Go toolchain to build and verify them
# against .github/tools/go.sum. Dependabot manages that module's versions;
# this script only ever installs whatever it currently pins.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
TOOLS_DIR="${REPO_ROOT}/.github/tools"
INSTALL_DIR="${HOME}/.local/bin"

mkdir -p "${INSTALL_DIR}"
GOBIN="${INSTALL_DIR}" go -C "${TOOLS_DIR}" install tool

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${INSTALL_DIR}" >> "${GITHUB_PATH}"
fi
