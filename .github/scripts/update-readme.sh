#!/usr/bin/env bash
#
# Regenerate README.md from README.md.tmpl and reusable workflows in
# .github/workflows using yq, gomplate, and Prettier.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

WORKFLOWS_JSON="$(mktemp)"
trap 'rm -f "${WORKFLOWS_JSON}"' EXIT

yq eval-all --output-format=json '
  [
    select(.name and ((.on == "workflow_call") or (.on | has("workflow_call"))))
    | {"file": (filename | sub("^.*/"; "")), "name": .name}
  ]
  | sort_by(.file)
' .github/workflows/*.yml > "${WORKFLOWS_JSON}"

gomplate \
  --datasource "workflows=file://${WORKFLOWS_JSON}?type=application/json" \
  --file README.md.tmpl --out README.md
npx -y prettier --write README.md
