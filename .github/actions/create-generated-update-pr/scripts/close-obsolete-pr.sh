#!/usr/bin/env bash
set -euo pipefail

: "${BRANCH:?BRANCH is required}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "::error::GH_TOKEN must be set in the step environment" >&2
  exit 1
fi

if [[ "${BRANCH}" == -* ]] || ! git check-ref-format "refs/heads/${BRANCH}" > /dev/null 2>&1; then
  echo "::error::branch is not a valid Git branch name: ${BRANCH}" >&2
  exit 1
fi

existing_pr_number="$(gh pr list --head "${BRANCH}" --state open --json number,isCrossRepository --jq '[.[] | select(.isCrossRepository == false)][0].number // empty')"

if [[ -n "${existing_pr_number}" ]]; then
  gh pr close "${existing_pr_number}" --comment "Closing: a later run produced no scoped changes, so this update is obsolete."
fi
