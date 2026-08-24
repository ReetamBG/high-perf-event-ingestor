#!/usr/bin/env bash
# Verifies that events actually reached storage, using any S3-compatible API.
# Backend-agnostic in the sense that it talks only to an S3 endpoint; it is
# run SEPARATELY from the load generator and never by it.
#
# Usage:
#   ./scripts/verify-storage.sh            # snapshot: object count + sizes
#   ./scripts/verify-storage.sh --watch 5  # re-check every 5s (drain watch)
#
# Config (env or stress-test/.env):
#   S3_ENDPOINT          e.g. http://localhost:8333
#   S3_BUCKET            e.g. my-bucket
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
#
# Requires the `aws` CLI. Load .env automatically if present:
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

S3_ENDPOINT="${S3_ENDPOINT:-http://localhost:8333}"
S3_BUCKET="${S3_BUCKET:-my-bucket}"
PREFIX="${S3_PREFIX:-}"

list_objects() {
  aws s3api list-objects-v2 \
    --endpoint-url "$S3_ENDPOINT" \
    --bucket "$S3_BUCKET" \
    ${PREFIX:+--prefix "$PREFIX"} \
    --output text --query 'Contents[].[Size]' 2>/dev/null || true
}

snapshot() {
  local label="${1:-snapshot}"
  local sizes total count avg
  sizes=$(list_objects)
  if [[ -z "$sizes" ]]; then
    echo "[$label] 0 objects"
    return
  fi
  count=$(echo "$sizes" | wc -l)
  total=$(echo "$sizes" | awk '{s+=$1} END {print s+0}')
  avg=$(( total / count ))
  echo "[$label] objects=$count total_bytes=$total avg_bytes=$avg"
}

if [[ "${1:-}" == "--watch" ]]; then
  interval="${2:-5}"
  while true; do
    snapshot "$(date +%H:%M:%S)"
    sleep "$interval"
  done
else
  snapshot "current"
  cat <<'EOF'

Tip: to measure how many events were PERSISTED by a test run:
  1. Run this script BEFORE the test  -> baseline count B
  2. Run the test, wait for downstream to drain
     (use --watch until the count stops increasing)
  3. Run this script AFTER           -> final count A
  persisted ~= A - B  (x objects-per-batch if your sink batches events
  into files; divide by batch size accordingly)
EOF
fi
