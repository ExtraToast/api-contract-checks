#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)

cp -- \
  "${repo_root}/examples/basic/live/openapi.json" \
  "${repo_root}/examples/basic/committed/openapi.json"
