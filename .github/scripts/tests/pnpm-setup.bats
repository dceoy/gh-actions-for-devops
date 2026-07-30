#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORKFLOWS="${REPO_ROOT}/.github/workflows"
}

pnpm_setup_value() {
  local workflow="$1" key="$2"
  yq -r \
    ".jobs.*.steps[] | select(.uses | startswith(\"pnpm/action-setup@\")) | .with.${key}" \
    "${workflow}"
}

@test "pnpm version defaults to package.json in every exposed input" {
  while IFS= read -r workflow; do
    run yq -r '.on.workflow_call.inputs.pnpm-version.default' "${workflow}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
  done < <(grep -rl --include='*.yml' '^      pnpm-version:$' "${WORKFLOWS}")
}

@test "explicit pnpm version remains an action override" {
  while IFS= read -r workflow; do
    run pnpm_setup_value "${workflow}" version
    [ "${status}" -eq 0 ]
    [ "${output}" = "\${{ inputs.pnpm-version || env.PNPM_VERSION }}" ]
  done < <(grep -rl --include='*.yml' 'pnpm/action-setup@' "${WORKFLOWS}")
}

@test "pnpm setup preserves latest fallback without package metadata" {
  while IFS= read -r workflow; do
    run grep -F "echo 'PNPM_VERSION=latest'" "${workflow}"
    [ "${status}" -eq 0 ]
  done < <(grep -rl --include='*.yml' 'pnpm/action-setup@' "${WORKFLOWS}")
}

@test "root pnpm project resolves the root package.json" {
  run pnpm_setup_value "${WORKFLOWS}/bats-test.yml" package_json_file
  [ "${status}" -eq 0 ]
  [ "${output}" = "package.json" ]
}

@test "nested pnpm projects resolve package.json from package-path" {
  while IFS= read -r workflow; do
    [[ "${workflow}" == */bats-test.yml ]] && continue
    run pnpm_setup_value "${workflow}" package_json_file
    [ "${status}" -eq 0 ]
    [ "${output}" = "\${{ format('{0}/package.json', inputs.package-path) }}" ]
  done < <(grep -rl --include='*.yml' 'pnpm/action-setup@' "${WORKFLOWS}")
}
