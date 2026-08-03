#!/usr/bin/env bash

set -u -o pipefail

main() {
  local target_repository="${TARGET_REPOSITORY:-}"
  local target_ref="${TARGET_REF:-}"

  if [[ -n "${target_repository}" ]]; then
    if [[ ! "${target_repository}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
      printf '::error::target-repository must be an owner/name pair.\n' >&2
      return 1
    fi
    if [[ ! "${target_ref}" =~ ^[0-9a-f]{40}$ ]]; then
      printf '::error::target-ref must be a full lowercase 40-character commit SHA when target-repository is set.\n' >&2
      return 1
    fi
    {
      printf 'owner=%s\n' "${target_repository%%/*}"
      printf 'name=%s\n' "${target_repository#*/}"
      printf 'repository=%s\n' "${target_repository}"
      printf 'ref=%s\n' "${target_ref}"
    } >> "${GITHUB_OUTPUT}"
    return 0
  fi

  if [[ -n "${target_ref}" ]]; then
    printf '::error::target-ref requires target-repository to be set.\n' >&2
    return 1
  fi

  {
    printf 'owner=\n'
    printf 'name=\n'
    printf 'repository=%s\n' "${EVENT_REPOSITORY:-}"
    if [[ "${EVENT_NAME:-}" == merge_group ]]; then
      printf 'ref=%s\n' "${MERGE_GROUP_HEAD_SHA:-}"
    else
      printf 'ref=%s\n' "${EVENT_SHA:-}"
    fi
  } >> "${GITHUB_OUTPUT}"
}

main
