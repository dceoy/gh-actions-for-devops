#!/usr/bin/env bash
set -euo pipefail

: "${BRANCH:?BRANCH is required}"
: "${BASE:?BASE is required}"
: "${COMMIT_MESSAGE:?COMMIT_MESSAGE is required}"
: "${GIT_USER_NAME:?GIT_USER_NAME is required}"
: "${GIT_USER_EMAIL:?GIT_USER_EMAIL is required}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "::error::GH_TOKEN must be set in the step environment" >&2
  exit 1
fi

if [[ "${BRANCH}" == -* ]] || ! git check-ref-format --branch "${BRANCH}" > /dev/null 2>&1; then
  echo "::error::branch is not a valid Git branch name: ${BRANCH}" >&2
  exit 1
fi

if [[ "${BRANCH}" == "${BASE}" ]]; then
  echo "::error::branch must not be the same as base: ${BRANCH}" >&2
  exit 1
fi

if [[ -z "${PATHS:-}" ]]; then
  echo "::error::paths input must not be empty" >&2
  exit 1
fi

pathspecs=()
while IFS= read -r pathspec; do
  [[ -n "${pathspec}" ]] && pathspecs+=("${pathspec}")
done <<< "${PATHS}"

if [[ ${#pathspecs[@]} -eq 0 ]]; then
  echo "::error::paths input produced no pathspecs" >&2
  exit 1
fi

gh auth setup-git

git checkout -B "${BRANCH}"
git -c user.name="${GIT_USER_NAME}" -c user.email="${GIT_USER_EMAIL}" commit --only --message "${COMMIT_MESSAGE}" -- "${pathspecs[@]}"
git push --force --set-upstream origin "${BRANCH}"

echo "commit-sha=$(git rev-parse HEAD)" >> "${GITHUB_OUTPUT}"
