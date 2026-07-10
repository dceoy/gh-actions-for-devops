#!/usr/bin/env bats
#
# Coverage for the fail-closed guard in update-readme.sh: README.md must
# never be (re)written when zero reusable workflows are detected or when
# workflow YAML fails to parse.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/update-readme.sh"
  FIXTURES_BIN="${BATS_TEST_DIRNAME}/fixtures/bin"
  TEST_REPO="$(mktemp -d)"
  export PATH="${FIXTURES_BIN}:${PATH}"

  cd "${TEST_REPO}" || exit
  git init -q
  git config user.email test@example.com
  git config user.name test
  mkdir -p .github/workflows

  cat > README.md.tmpl <<'EOF'
# Workflows
{{ range (datasource "workflows") -}}
- {{ .file }}: {{ .name }}
{{ end -}}
EOF
}

teardown() {
  cd /
  rm -rf "${TEST_REPO}"
}

write_reusable_workflow() {
  local file="$1" name="$2"
  cat > ".github/workflows/${file}" <<EOF
name: ${name}
on:
  workflow_call:
    inputs: {}
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo noop
EOF
}

write_non_reusable_workflow() {
  local file="$1"
  cat > ".github/workflows/${file}" <<EOF
name: Not reusable
on:
  push:
    branches: [main]
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo noop
EOF
}

@test "succeeds and renders sorted entries when one or more reusable workflows exist" {
  write_reusable_workflow "b-workflow.yml" "B Workflow"
  write_reusable_workflow "a-workflow.yml" "A Workflow"
  write_non_reusable_workflow "not-reusable.yml"

  run "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [ -f README.md ]
  grep -q "a-workflow.yml: A Workflow" README.md
  grep -q "b-workflow.yml: B Workflow" README.md
  run ! grep -q "not-reusable.yml" README.md
  # a-workflow.yml (sorted first) must appear before b-workflow.yml
  [ "$(grep -n 'a-workflow.yml' README.md | cut -d: -f1)" -lt "$(grep -n 'b-workflow.yml' README.md | cut -d: -f1)" ]
}

@test "fails without modifying README.md when zero reusable workflows are found" {
  write_non_reusable_workflow "not-reusable.yml"
  echo "SENTINEL-DO-NOT-CHANGE" > README.md

  run "${SCRIPT}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"::error::"*"no reusable"* ]]
  [ "$(cat README.md)" = "SENTINEL-DO-NOT-CHANGE" ]
}

@test "fails without modifying README.md when workflow YAML is malformed" {
  write_reusable_workflow "a-workflow.yml" "A Workflow"
  printf 'name: broken\non:\n  bad: [unterminated\n' > .github/workflows/broken.yml
  echo "SENTINEL-DO-NOT-CHANGE" > README.md

  run "${SCRIPT}"

  [ "${status}" -ne 0 ]
  [ "$(cat README.md)" = "SENTINEL-DO-NOT-CHANGE" ]
}
