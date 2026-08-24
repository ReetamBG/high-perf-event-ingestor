#!/usr/bin/env bash
# Samples CPU / memory usage of a Docker container to a CSV file.
# Run this IN A SEPARATE TERMINAL while the load test is running.
#
# Usage:
#   ./scripts/collect-container-metrics.sh [output.csv]
#
# Config (env):
#   CONTAINER_NAME   container to sample        (default: ingestion-service)
#   SAMPLE_INTERVAL  seconds between samples    (default: 1)
#
# Stop with Ctrl+C. Output: results/container-metrics-<ts>.csv by default.
set -euo pipefail

cd "$(dirname "$0")/.." # stress-test root

CONTAINER_NAME="${CONTAINER_NAME:-ingestion-service}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-1}"
DEFAULT_OUT="results/container-metrics-$(date +%Y%m%d-%H%M%S).csv"
OUT="${1:-$DEFAULT_OUT}"

if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "error: container '$CONTAINER_NAME' not found" >&2
  exit 1
fi

echo "sampling '$CONTAINER_NAME' every ${SAMPLE_INTERVAL}s -> $OUT (Ctrl+C to stop)"

printf 'timestamp,cpu_percent,mem_used,mem_limit,mem_percent,net_io,block_io\n' > "$OUT"

stop() { echo; echo "wrote $(wc -l < "$OUT") lines to $OUT"; exit 0; }
trap stop INT TERM

while true; do
  row=$(docker stats --no-stream \
    --format '{{.CPUPerc}};{{.MemUsage}};{{.MemPerc}};{{.NetIO}};{{.BlockIO}}' \
    "$CONTAINER_NAME" 2>/dev/null || true)
  if [[ -n "$row" ]]; then
    IFS=';' read -r cpu mem mempct net blk <<< "$row"
    mem_used="${mem%% /*}"
    mem_limit="${mem##*/ }"
    printf '%s,%s,%s,%s,%s,%s,%s\n' \
      "$(date -Is)" "$cpu" "$mem_used" "$mem_limit" "$mempct" "$net" "$blk" >> "$OUT"
  fi
  sleep "$SAMPLE_INTERVAL"
done
