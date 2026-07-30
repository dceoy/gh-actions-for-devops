#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(git -C "${BATS_TEST_DIRNAME}" rev-parse --show-toplevel)"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures/pnpm"
  WORKFLOWS=(
    bats-test.yml
    html-lint-and-scan.yml
    json-lint.yml
    typescript-package-format-and-pr.yml
    typescript-package-lint-and-scan.yml
    typescript-package-script.yml
  )
}

pnpm_step_value() {
  local workflow="$1"
  local key="$2"

  yq -r ".jobs.*.steps[] | select(.uses == \"pnpm/action-setup@0ebf47130e4866e96fce0953f49152a61190b271\") | .with.\"${key}\"" \
    "${REPO_ROOT}/.github/workflows/${workflow}"
}

@test "every pnpm setup workflow defaults to repository version inference" {
  for workflow in "${WORKFLOWS[@]}"; do
    default_version="$(
      yq -r '.on.workflow_call.inputs."pnpm-version".default' \
        "${REPO_ROOT}/.github/workflows/${workflow}"
    )"
    [ -z "${default_version}" ]
    # shellcheck disable=SC2016
    [ "$(pnpm_step_value "${workflow}" version)" = '${{ inputs.pnpm-version }}' ]
  done
}

@test "root and nested workflows resolve package.json relative to the repository root" {
  [ "$(yq -r .packageManager "${FIXTURES}/root/package.json")" = "pnpm@11.16.0" ]
  [ "$(yq -r .packageManager "${FIXTURES}/nested/apps/site/package.json")" = "pnpm@11.16.0" ]

  [ "$(pnpm_step_value bats-test.yml package_json_file)" = "package.json" ]
  for workflow in \
    html-lint-and-scan.yml \
    json-lint.yml \
    typescript-package-format-and-pr.yml \
    typescript-package-lint-and-scan.yml \
    typescript-package-script.yml; do
    [ "$(pnpm_step_value "${workflow}" package_json_file)" = "\${{ format('{0}/package.json', inputs.package-path) }}" ]
  done
}
