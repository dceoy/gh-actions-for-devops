#!/usr/bin/env bash
#
# Ensure the yq and gomplate CLIs declared in aqua.yaml are installed and on
# PATH. aqua itself (installed beforehand via aquaproj/aqua-installer) owns
# the versions and checksum verification; this script only ever installs or
# verifies whatever aqua.yaml currently pins.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

if ! command -v aqua >/dev/null 2>&1; then
  echo "::error::aqua is not installed; install it via aquaproj/aqua-installer before running this script" >&2
  exit 1
fi

(cd "${REPO_ROOT}" && aqua install)

for cmd in yq gomplate; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "::error::${cmd} is not available on PATH after aqua install" >&2
    exit 1
  fi
done
