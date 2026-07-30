#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORKFLOWS="${REPO_ROOT}/.github/workflows"
}

pnpm_setup_value() {
  local workflow="$1" key="$2"
  yq -r \
    ".jobs.*.steps[] | select(.uses | test(\"^pnpm/action-setup@\")) | .with.${key}" \
    "${workflow}"
}

@test "pnpm version defaults to package.json in every exposed input" {
  local count=0
  while IFS= read -r workflow; do
    run yq -r '.on.workflow_call.inputs.pnpm-version.default' "${workflow}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' '^      pnpm-version:$' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "explicit pnpm version remains an action override" {
  local count=0
  while IFS= read -r workflow; do
    run pnpm_setup_value "${workflow}" version
    [ "${status}" -eq 0 ]
    [ "${output}" = "\${{ inputs.pnpm-version || env.PNPM_VERSION }}" ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'pnpm/action-setup@' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "pnpm setup preserves latest fallback without package metadata" {
  local count=0
  while IFS= read -r workflow; do
    run grep -F "echo 'PNPM_VERSION=latest'" "${workflow}"
    [ "${status}" -eq 0 ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'pnpm/action-setup@' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}

@test "root pnpm project resolves the root package.json" {
  run pnpm_setup_value "${WORKFLOWS}/bats-test.yml" package_json_file
  [ "${status}" -eq 0 ]
  [ "${output}" = "package.json" ]
}

@test "nested pnpm projects resolve package.json from package-path" {
  local count=0
  while IFS= read -r workflow; do
    [[ "${workflow}" == */bats-test.yml ]] && continue
    run pnpm_setup_value "${workflow}" package_json_file
    [ "${status}" -eq 0 ]
    [ "${output}" = "\${{ format('{0}/package.json', inputs.package-path) }}" ]
    count=$((count + 1))
  done < <(grep -rl --include='*.yml' 'pnpm/action-setup@' "${WORKFLOWS}")
  [ "${count}" -gt 0 ]
}
