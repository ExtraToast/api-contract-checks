#!/usr/bin/env bash

set -euo pipefail

json=false
number=""
description=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      json=true
      ;;
    --number)
      shift
      [ "$#" -gt 0 ] || { echo "ERROR: --number requires a value" >&2; exit 1; }
      number=$1
      ;;
    --help|-h)
      echo "Usage: create-new-feature.sh [--json] [--number N] <description>"
      exit 0
      ;;
    --*)
      echo "ERROR: unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$description" ]; then
        description=$1
      else
        description="$description $1"
      fi
      ;;
  esac
  shift
done

[ -n "$description" ] || { echo "ERROR: feature description is required" >&2; exit 1; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(git -C "$script_dir/../../.." rev-parse --show-toplevel 2>/dev/null || (CDPATH= cd -- "$script_dir/../../.." && pwd -P))

slug=$(printf '%s\n' "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g' | awk '
{
  count = 0
  for (i = 1; i <= NF; i++) {
    if ($i == "the" || $i == "and" || $i == "for" || $i == "with" || $i == "from" || $i == "that" || $i == "this" || $i == "into") continue
    words[++count] = $i
    if (count == 4) break
  }
  if (count == 0) print "feature"
  else {
    for (i = 1; i <= count; i++) printf "%s%s", (i == 1 ? "" : "-"), words[i]
    printf "\n"
  }
}')

if [ -z "$number" ]; then
  highest=0
  for path in "$repo_root"/specs/[0-9][0-9][0-9]-*; do
    [ -d "$path" ] || continue
    base=$(basename "$path")
    current=${base%%-*}
    [ "$current" -gt "$highest" ] && highest=$current
  done
  number=$((highest + 1))
fi

feature_number=$(printf '%03d' "$number")
feature_dir="$repo_root/specs/$feature_number-$slug"
spec_file="$feature_dir/spec.md"
template="$repo_root/.specify/templates/spec-template.md"

mkdir -p "$feature_dir"
if [ ! -f "$spec_file" ]; then
  sed \
    -e "s/{{FEATURE_NAME}}/$feature_number-$slug/g" \
    -e "s/{{DATE}}/$(date +%F)/g" \
    "$template" > "$spec_file"
fi

cat > "$repo_root/.specify/feature.json" <<EOF
{"FEATURE_DIR":"$feature_dir","SPEC_FILE":"$spec_file","FEATURE_NUMBER":"$feature_number"}
EOF

if [ "$json" = true ]; then
  printf '{"FEATURE_DIR":"%s","SPEC_FILE":"%s","FEATURE_NUMBER":"%s"}\n' "$feature_dir" "$spec_file" "$feature_number"
else
  printf 'FEATURE_DIR: %s\nSPEC_FILE: %s\n' "$feature_dir" "$spec_file"
fi
