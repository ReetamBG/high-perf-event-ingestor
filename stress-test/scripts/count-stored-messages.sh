#!/usr/bin/env bash
# Counts the exact number of MESSAGES persisted to S3-compatible storage,
# by downloading every object created after a UTC cutoff timestamp and
# counting its records (JSONL: one message per line).
#
# This is exact regardless of how many messages each object contains —
# batching (e.g. N msgs OR T seconds, whichever first) makes object sizes
# ragged, but line counts stay correct.
#
# Usage:
#   ./scripts/count-stored-messages.sh <UTC-cutoff> [--json]
#     e.g. ./scripts/count-stored-messages.sh 2026-08-24T12:00:00Z
#
# Options:
#   --json        machine-readable output
#
# Config (env or ../.env):
#   S3_ENDPOINT, S3_BUCKET, S3_PREFIX (optional)
#   FETCH_CONCURRENCY   parallel downloads   (default: 8)
#
# Downloads go to a temp dir under results/ and are deleted afterwards.
set -uo pipefail

cd "$(dirname "$0")/.."
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

usage() { echo "usage: $0 <UTC-cutoff> [--json]   e.g. $0 2026-08-24T12:00:00Z" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
CUTOFF="$1"; shift
JSON_OUT=0
[[ "${1:-}" == "--json" ]] && JSON_OUT=1

S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_BUCKET="${S3_BUCKET:-}"
S3_PREFIX="${S3_PREFIX:-}"
FETCH_CONCURRENCY="${FETCH_CONCURRENCY:-8}"

command -v aws >/dev/null 2>&1 || { echo "error: aws CLI required" >&2; exit 1; }
[[ -n "$S3_ENDPOINT" && -n "$S3_BUCKET" ]] || { echo "error: set S3_ENDPOINT and S3_BUCKET" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
TMP="results/.tmp-count-$STAMP"
mkdir -p "$TMP"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

# ---- list object keys created after the cutoff ----
KEYS="$TMP/keys.txt"
QUERY='Contents[?LastModified>=`'"$CUTOFF"'`].[Key]'
if ! aws s3api list-objects-v2 \
      --endpoint-url "$S3_ENDPOINT" --bucket "$S3_BUCKET" \
      ${S3_PREFIX:+--prefix "$S3_PREFIX"} \
      --query "$QUERY" --output text > "$KEYS" 2>"$TMP/list.err"; then
  echo "error: listing failed: $(cat "$TMP/list.err")" >&2
  exit 1
fi
# strip CR (text output), drop empties
tr -d '\r' < "$KEYS" | grep -v '^[[:space:]]*$' > "$KEYS.clean" || true
mv "$KEYS.clean" "$KEYS"

TOTAL_OBJECTS=$(wc -l < "$KEYS")
if (( TOTAL_OBJECTS == 0 )); then
  if (( JSON_OUT )); then
    printf '{"objects":0,"messages":0,"bytes":0,"cutoff":"%s"}\n' "$CUTOFF"
  else
    echo "objects=0 messages=0 bytes=0"
  fi
  exit 0
fi

# ---- download + count lines, in parallel ----
count_one() {
  local key="$1"
  local f="$TMP/obj-$2"
  if aws s3api get-object --endpoint-url "$S3_ENDPOINT" \
       --bucket "$S3_BUCKET" --key "$key" "$f" >/dev/null 2>&1; then
    wc -l < "$f"
    rm -f "$f"
  else
    echo 0
  fi
}
export -f count_one
export S3_ENDPOINT S3_BUCKET TMP

export -f count_one
export S3_ENDPOINT S3_BUCKET TMP

# "<idx> <key>" pairs (keys are uuid-style, no whitespace)
awk '{print NR" "$0}' "$KEYS" > "$KEYS.idx"

LINES_FILE="$TMP/lines.txt"
xargs < "$KEYS.idx" -n 2 -P "$FETCH_CONCURRENCY" bash -c '
  n=$(count_one "$1" "$0")
  printf "%s\n" "$n"
' > "$LINES_FILE" 2>>"$TMP/fetch.err"

# fallback sequential pass if parallel produced nothing
if [[ ! -s "$LINES_FILE" ]]; then
  while read -r idx key; do
    count_one "$key" "$idx" >> "$LINES_FILE"
  done < "$KEYS.idx"
fi

MESSAGES=$(awk '{s+=$1} END{print s+0}' "$LINES_FILE")

# total bytes of the counted objects
BYTES=$(aws s3api list-objects-v2 \
  --endpoint-url "$S3_ENDPOINT" --bucket "$S3_BUCKET" \
  ${S3_PREFIX:+--prefix "$S3_PREFIX"} \
  --query 'Contents[?LastModified>=`'"$CUTOFF"'`].[Size]' --output text 2>/dev/null \
  | tr -d '\r' | awk '{s+=$1} END{print s+0}')

if (( JSON_OUT )); then
  printf '{"objects":%d,"messages":%d,"bytes":%d,"cutoff":"%s","concurrency":%d}\n' \
    "$TOTAL_OBJECTS" "$MESSAGES" "$BYTES" "$CUTOFF" "$FETCH_CONCURRENCY"
else
  echo "objects=$TOTAL_OBJECTS messages=$MESSAGES bytes=$BYTES"
fi
