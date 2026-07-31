#!/usr/bin/env bash
set -euo pipefail

: "${BRANCH:?BRANCH is required}"
: "${BASE:?BASE is required}"
: "${TITLE:?TITLE is required}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "::error::GH_TOKEN must be set in the step environment" >&2
  exit 1
fi

if [[ "${BRANCH}" == -* ]] || ! git check-ref-format --branch "${BRANCH}" > /dev/null 2>&1; then
  echo "::error::branch is not a valid Git branch name: ${BRANCH}" >&2
  exit 1
fi

labels=()
if [[ -n "${LABELS:-}" ]]; then
  while IFS= read -r label; do
    [[ -n "${label}" ]] && labels+=("${label}")
  done < <(tr ',' '\n' <<< "${LABELS}")
fi

existing_pr_number="$(gh pr list --head "${BRANCH}" --base "${BASE}" --state open --json number --jq '.[0].number // empty')"

if [[ -n "${existing_pr_number}" ]]; then
  gh pr edit "${existing_pr_number}" --title "${TITLE}" --body "${BODY:-}"
  for label in "${labels[@]}"; do
    gh pr edit "${existing_pr_number}" --add-label "${label}"
  done
  pr_number="${existing_pr_number}"
else
  create_args=(--title "${TITLE}" --body "${BODY:-}" --base "${BASE}" --head "${BRANCH}")
  [[ "${DRAFT:-false}" == "true" ]] && create_args+=(--draft)
  for label in "${labels[@]}"; do
    create_args+=(--label "${label}")
  done
  gh pr create "${create_args[@]}"
  pr_number="$(gh pr view "${BRANCH}" --json number --jq '.number')"
fi

pr_url="$(gh pr view "${pr_number}" --json url --jq '.url')"

{
  echo "pr-number=${pr_number}"
  echo "pr-url=${pr_url}"
} >> "${GITHUB_OUTPUT}"
