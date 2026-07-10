#!/usr/bin/env bats
#
# Coverage for the hardened, fail-closed checksum replacement in
# sync-tool-checksums.sh. A fake `curl` under fixtures/bin serves canned
# yq/gomplate release-checksum assets (see fixtures/bin/curl) so these tests
# never touch the network; the resolved digests are fixed and known.

setup() {
  SCRIPT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/sync-tool-checksums.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  TEST_REPO="$(mktemp -d)"
  export PATH="${FIXTURES}/bin:${PATH}"
  unset GOMPLATE_CHECKSUMS_FIXTURE

  # Digests the fake curl fixtures resolve to for each tool/architecture.
  YQ_AMD64="8c346d08fd7cfb330d8326bc7a13f926892113a2a5bc2b3ec4fc2ded3fbee3a6"
  YQ_ARM64="d7f58290a274c3d40c995c71fdedfe3858d602ee0dc1798795903994d995f62e"
  GOMPLATE_AMD64="000bda861f669bf939d93b7e39b4e57d54a8d12c51773dcc597b62216f94ba30"
  GOMPLATE_ARM64="f08d0fe31d15b31f5765febe0cc4e3cd07b49da6d898cd8e55e9fa4c4da7980b"

  cd "${TEST_REPO}" || exit
  git init -q
  git config user.email test@example.com
  git config user.name test
  mkdir -p .github/workflows
}

teardown() {
  cd /
  rm -rf "${TEST_REPO}"
}

ci_yml_path() {
  echo ".github/workflows/ci.yml"
}

write_ci_yml() {
  cat > "$(ci_yml_path)" <<EOF
name: CI/CD
jobs:
  update-readme-md:
    env:
      # renovate: datasource=github-releases depName=mikefarah/yq
      YQ_VERSION: v4.53.3
${1}
      # renovate: datasource=github-releases depName=hairyhenderson/gomplate
      GOMPLATE_VERSION: v5.1.0
${2}
EOF
}

placeholder64() {
  # A distinct, obviously-fake 64-char lowercase hex placeholder ending in $1.
  printf '%064d' 0 | sed "s/0\$/${1}/"
}

@test "successfully replaces all four checksums" {
  write_ci_yml \
    "      YQ_SHA256_AMD64: $(placeholder64 1)
      YQ_SHA256_ARM64: $(placeholder64 2)" \
    "      GOMPLATE_SHA256_AMD64: $(placeholder64 3)
      GOMPLATE_SHA256_ARM64: $(placeholder64 4)"

  run "${SCRIPT}"

  [ "${status}" -eq 0 ]
  grep -qx "      YQ_SHA256_AMD64: ${YQ_AMD64}" "$(ci_yml_path)"
  grep -qx "      YQ_SHA256_ARM64: ${YQ_ARM64}" "$(ci_yml_path)"
  grep -qx "      GOMPLATE_SHA256_AMD64: ${GOMPLATE_AMD64}" "$(ci_yml_path)"
  grep -qx "      GOMPLATE_SHA256_ARM64: ${GOMPLATE_ARM64}" "$(ci_yml_path)"
}

@test "preserves quoting and inline comments when replacing" {
  write_ci_yml \
    "      YQ_SHA256_AMD64: \"$(placeholder64 1)\"  # amd64
      YQ_SHA256_ARM64: '$(placeholder64 2)'" \
    "      GOMPLATE_SHA256_AMD64: $(placeholder64 3)
      GOMPLATE_SHA256_ARM64: $(placeholder64 4)  # arm64"

  run "${SCRIPT}"

  [ "${status}" -eq 0 ]
  grep -qx "      YQ_SHA256_AMD64: \"${YQ_AMD64}\"  # amd64" "$(ci_yml_path)"
  grep -qx "      YQ_SHA256_ARM64: '${YQ_ARM64}'" "$(ci_yml_path)"
  grep -qx "      GOMPLATE_SHA256_AMD64: ${GOMPLATE_AMD64}" "$(ci_yml_path)"
  grep -qx "      GOMPLATE_SHA256_ARM64: ${GOMPLATE_ARM64}  # arm64" "$(ci_yml_path)"
}

@test "fails and leaves the file untouched when a checksum variable is missing" {
  write_ci_yml \
    "      YQ_SHA256_AMD64: $(placeholder64 1)" \
    "      GOMPLATE_SHA256_AMD64: $(placeholder64 3)
      GOMPLATE_SHA256_ARM64: $(placeholder64 4)"
  cp "$(ci_yml_path)" original.yml

  run "${SCRIPT}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"::error::"*"YQ_SHA256_ARM64"* ]]
  diff -u original.yml "$(ci_yml_path)"
}

@test "fails and leaves the file untouched when a checksum variable is duplicated" {
  write_ci_yml \
    "      YQ_SHA256_AMD64: $(placeholder64 1)
      YQ_SHA256_ARM64: $(placeholder64 2)
      YQ_SHA256_ARM64: $(placeholder64 9)" \
    "      GOMPLATE_SHA256_AMD64: $(placeholder64 3)
      GOMPLATE_SHA256_ARM64: $(placeholder64 4)"
  cp "$(ci_yml_path)" original.yml

  run "${SCRIPT}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"::error::"*"YQ_SHA256_ARM64"*"found 2"* ]]
  diff -u original.yml "$(ci_yml_path)"
}

@test "fails and leaves the file untouched when the current checksum is malformed" {
  write_ci_yml \
    "      YQ_SHA256_AMD64: $(placeholder64 1)
      YQ_SHA256_ARM64: not-a-valid-checksum" \
    "      GOMPLATE_SHA256_AMD64: $(placeholder64 3)
      GOMPLATE_SHA256_ARM64: $(placeholder64 4)"
  cp "$(ci_yml_path)" original.yml

  run "${SCRIPT}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"::error::"*"YQ_SHA256_ARM64"* ]]
  diff -u original.yml "$(ci_yml_path)"
}

@test "fails and leaves the file untouched when upstream is missing a checksum" {
  export GOMPLATE_CHECKSUMS_FIXTURE=gomplate_checksums_invalid
  write_ci_yml \
    "      YQ_SHA256_AMD64: $(placeholder64 1)
      YQ_SHA256_ARM64: $(placeholder64 2)" \
    "      GOMPLATE_SHA256_AMD64: $(placeholder64 3)
      GOMPLATE_SHA256_ARM64: $(placeholder64 4)"
  cp "$(ci_yml_path)" original.yml

  run "${SCRIPT}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"::error::"*"GOMPLATE_SHA256_AMD64"* ]]
  diff -u original.yml "$(ci_yml_path)"
}

@test "is idempotent on rerun" {
  write_ci_yml \
    "      YQ_SHA256_AMD64: $(placeholder64 1)
      YQ_SHA256_ARM64: $(placeholder64 2)" \
    "      GOMPLATE_SHA256_AMD64: $(placeholder64 3)
      GOMPLATE_SHA256_ARM64: $(placeholder64 4)"

  run "${SCRIPT}"
  [ "${status}" -eq 0 ]
  cp "$(ci_yml_path)" after-first-run.yml

  run "${SCRIPT}"
  [ "${status}" -eq 0 ]
  diff -u after-first-run.yml "$(ci_yml_path)"
}
