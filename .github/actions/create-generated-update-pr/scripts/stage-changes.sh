#!/usr/bin/env bash
set -euo pipefail

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

git add -A -- "${pathspecs[@]}"

if git diff --cached --quiet -- "${pathspecs[@]}"; then
  echo "changed=false" >> "${GITHUB_OUTPUT}"
else
  echo "changed=true" >> "${GITHUB_OUTPUT}"
fi
