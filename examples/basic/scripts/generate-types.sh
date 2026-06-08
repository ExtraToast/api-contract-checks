#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
spec_path=${1:-"${repo_root}/examples/basic/committed/openapi.json"}
output_path=${2:-"${repo_root}/examples/basic/types/generated.ts"}

title=$(sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$spec_path" | head -n 1)
version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$spec_path" | head -n 1)

if [[ -z $title || -z $version ]]; then
  printf 'unable to read title/version from %s\n' "$spec_path" >&2
  exit 1
fi

cat >"$output_path" <<EOF
/**
 * AUTO-GENERATED. Do not edit by hand.
 * Source: examples/basic/committed/openapi.json
 */
export type ApiTitle = "${title}"
export type ApiVersion = "${version}"
EOF
