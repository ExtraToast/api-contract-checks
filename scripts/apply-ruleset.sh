#!/usr/bin/env bash
# Apply the org-standard branch ruleset (.github/rulesets/main.json) to a repo.
#
# Every ExtraToast repo must carry the common ruleset that makes the single
# "Pipeline Complete" status check required before any PR can merge. This
# script is idempotent: it creates the "Main" ruleset if absent, otherwise
# updates the existing one in place.
#
# Usage: scripts/apply-ruleset.sh <owner/repo>   (default: current repo)
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
RULESET_JSON="$(dirname "$0")/../.github/rulesets/main.json"

existing_id="$(gh api "/repos/$REPO/rulesets" --jq '.[] | select(.name=="Main") | .id' 2>/dev/null || true)"

if [[ -n "$existing_id" ]]; then
  echo "Updating ruleset 'Main' ($existing_id) on $REPO"
  gh api -X PUT "/repos/$REPO/rulesets/$existing_id" --input "$RULESET_JSON" >/dev/null
else
  echo "Creating ruleset 'Main' on $REPO"
  gh api -X POST "/repos/$REPO/rulesets" --input "$RULESET_JSON" >/dev/null
fi
echo "Done. 'Pipeline Complete' is now the required check on the default branch of $REPO."
