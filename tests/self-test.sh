#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

new_case() {
  local name=$1
  local case_root="${tmp_dir}/${name}/repo"

  mkdir -p -- "${case_root}/scripts"
  cp -a -- "${repo_root}/examples" "${case_root}/examples"
  cp -- "${repo_root}/scripts/api-contract-checks.sh" "${case_root}/scripts/api-contract-checks.sh"
  chmod +x -- "${case_root}/scripts/api-contract-checks.sh" \
    "${case_root}/examples/basic/scripts/export-openapi.sh" \
    "${case_root}/examples/basic/scripts/generate-types.sh"

  printf '%s\n' "$case_root"
}

assert_contains() {
  local haystack=$1
  local needle=$2

  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf 'actual output:\n%s\n' "$haystack" >&2
    exit 1
  fi
}

clean_root=$(new_case clean)
(
  cd -- "$clean_root"
  scripts/api-contract-checks.sh --profiles-dir examples/basic/profiles --only example
)

spec_root=$(new_case spec-drift)
(
  cd -- "$spec_root"
  sed -i 's/"title": "Example Contract"/"title": "Changed Contract"/' examples/basic/live/openapi.json
  if output=$(scripts/api-contract-checks.sh --profile-file examples/basic/profiles/example.conf 2>&1); then
    printf 'expected spec drift check to fail\n' >&2
    exit 1
  fi
  assert_contains "$output" "stage: openapi-spec"
  assert_contains "$output" "path: examples/basic/committed/openapi.json"
  assert_contains "$output" "guidance: examples/basic/scripts/export-openapi.sh && examples/basic/scripts/generate-types.sh"
)

types_root=$(new_case types-drift)
(
  cd -- "$types_root"
  sed -i 's/Example Contract/Stale Contract/' examples/basic/types/generated.ts
  if output=$(scripts/api-contract-checks.sh --profile-file examples/basic/profiles/example.conf 2>&1); then
    printf 'expected types drift check to fail\n' >&2
    exit 1
  fi
  assert_contains "$output" "stage: types"
  assert_contains "$output" "path: examples/basic/types/generated.ts"
  assert_contains "$output" "guidance: examples/basic/scripts/export-openapi.sh && examples/basic/scripts/generate-types.sh"
)

printf 'self-test passed\n'
