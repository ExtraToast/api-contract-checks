#!/usr/bin/env bash

set -euo pipefail

json=false
paths_only=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      json=true
      ;;
    --paths-only)
      paths_only=true
      ;;
    --help|-h)
      echo "Usage: check-prerequisites.sh [--json] [--paths-only]"
      exit 0
      ;;
    --*)
      echo "ERROR: unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(git -C "$script_dir/../../.." rev-parse --show-toplevel 2>/dev/null || (CDPATH= cd -- "$script_dir/../../.." && pwd -P))
feature_json="$repo_root/.specify/feature.json"

[ -f "$feature_json" ] || { echo "ERROR: .specify/feature.json not found" >&2; exit 1; }

feature_dir=$(sed -n 's/.*"FEATURE_DIR":"\([^"]*\)".*/\1/p' "$feature_json")
spec_file=$(sed -n 's/.*"SPEC_FILE":"\([^"]*\)".*/\1/p' "$feature_json")

[ -d "$feature_dir" ] || { echo "ERROR: feature directory not found: $feature_dir" >&2; exit 1; }
[ -f "$spec_file" ] || { echo "ERROR: spec file not found: $spec_file" >&2; exit 1; }

if [ "$paths_only" = true ] || [ "$json" = true ]; then
  printf '{"FEATURE_DIR":"%s","SPEC_FILE":"%s"}\n' "$feature_dir" "$spec_file"
else
  printf 'FEATURE_DIR: %s\nSPEC_FILE: %s\n' "$feature_dir" "$spec_file"
fi
