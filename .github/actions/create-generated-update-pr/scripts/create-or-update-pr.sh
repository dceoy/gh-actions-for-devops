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

if [[ "${BASE}" == -* ]] || ! git check-ref-format --branch "${BASE}" > /dev/null 2>&1; then
  echo "::error::base is not a valid Git branch name: ${BASE}" >&2
  exit 1
fi

labels=()
if [[ -n "${LABELS:-}" ]]; then
  while IFS= read -r label; do
    [[ -n "${label}" ]] && labels+=("${label}")
  done < <(tr ',' '\n' <<< "${LABELS}")
fi

draft="${DRAFT:-false}"

existing_pr_number="$(gh pr list --head "${BRANCH}" --state open --json number --jq '.[0].number // empty')"

if [[ -n "${existing_pr_number}" ]]; then
  gh pr edit "${existing_pr_number}" --title "${TITLE}" --body "${BODY:-}" --base "${BASE}"
  for label in "${labels[@]}"; do
    gh pr edit "${existing_pr_number}" --add-label "${label}"
  done
  existing_is_draft="$(gh pr view "${existing_pr_number}" --json isDraft --jq '.isDraft')"
  if [[ "${draft}" == "true" && "${existing_is_draft}" == "false" ]]; then
    gh pr ready "${existing_pr_number}" --undo
  elif [[ "${draft}" != "true" && "${existing_is_draft}" == "true" ]]; then
    gh pr ready "${existing_pr_number}"
  fi
  pr_number="${existing_pr_number}"
else
  create_args=(--title "${TITLE}" --body "${BODY:-}" --base "${BASE}" --head "${BRANCH}")
  [[ "${draft}" == "true" ]] && create_args+=(--draft)
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
