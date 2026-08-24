#!/usr/bin/env bash
# =============================================================================
# THE ULTIMATE BENCHMARK — one command, one results file.
#
# Pipeline:
#   preflight checks
#     -> start CPU/RAM monitoring
#     -> storage baseline
#     -> PROGRESSIVE test  -> drain
#     -> SUSTAINED test    -> drain
#     -> BURST test        -> drain
#     -> storage verification
#     -> stop monitoring
#     -> merge everything into results/full-benchmark-<ts>.json
#
# Usage:
#   ./scripts/run-full-benchmark.sh
#
# Config: same env vars as the individual scenarios (see ../README.md), taken
# from the environment or auto-loaded from stress-test/.env, plus:
#   DRAIN_TIMEOUT   max seconds to wait for downstream drain (default 180)
#   DRAIN_POLL      seconds between drain checks          (default 5)
#   DRAIN_STABLE    consecutive stable checks = drained   (default 3)
#
# Requires: k6, docker (resource monitoring), aws CLI (optional; storage steps
# are skipped cleanly when absent).
# =============================================================================
set -uo pipefail

ST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ST_ROOT"

# ---------- config ----------
TARGET_URL="${TARGET_URL:-http://localhost:8080/events/ingest}"
CONTAINER_NAME="${CONTAINER_NAME:-ingestion-service}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-1}"
DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-180}"
DRAIN_POLL="${DRAIN_POLL:-5}"
DRAIN_STABLE="${DRAIN_STABLE:-3}"

# auto-load .env without clobbering real env vars
if [[ -f .env ]]; then
  while IFS='=' read -r k v; do
    [[ "$k" =~ ^[[:space:]]*#.*$ || -z "$k" ]] && continue
    v="${v%\"}"; v="${v#\"}"
    if [[ -z "${!k:-}" ]]; then export "$k=$v"; fi
  done < .env
fi

# ---------- preflight ----------
say()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v k6 >/dev/null 2>&1 || die "k6 not installed (https://grafana.com/docs/k6/latest/set-up/install-k6/)"

DOCKER_OK=0
if command -v docker >/dev/null 2>&1 && docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  DOCKER_OK=1
else
  info "container '$CONTAINER_NAME' not found — CPU/RAM monitoring will be skipped"
fi

STORAGE_OK=0
if command -v aws >/dev/null 2>&1 && [[ -n "${S3_ENDPOINT:-}" && -n "${S3_BUCKET:-}" ]]; then
  STORAGE_OK=1
else
  info "aws CLI / S3_ENDPOINT / S3_BUCKET incomplete — storage checks & drain detection skipped"
fi

if [[ -z "${JWT_TOKEN:-}" ]]; then
  [[ -n "${JWT_SECRET:-}" ]] || die "set JWT_TOKEN (or JWT_SECRET) — see scripts/generate-jwt.sh"
  JWT_TOKEN="$(./scripts/generate-jwt.sh "$JWT_SECRET" 86400)"
  export JWT_TOKEN
  info "minted a fresh 24h JWT from JWT_SECRET"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"   # cutoff for "objects created by this benchmark"
CSV="results/full-benchmark-$STAMP-resources.csv"
OUT_JSON="results/full-benchmark-$STAMP.json"
mkdir -p results

# ---------- resource sampler (background) ----------
SAMPLER_PID=""
K6_PID=""
PHASE="idle"

start_sampler() {
  [[ $DOCKER_OK = 1 ]] || return 0
  printf 'timestamp,phase,cpu_percent,mem_used,mem_limit,mem_percent\n' > "$CSV"
  (
    while true; do
      row=$(docker stats --no-stream \
        --format '{{.CPUPerc}} {{.MemUsage}} {{.MemPerc}}' \
        "$CONTAINER_NAME" 2>/dev/null || true)
      if [[ -n "$row" ]]; then
        cpu="${row%% *}"
        rest="${row#* }"
        mem="${rest%% *}"
        mempct="${rest##* }"
        printf '%s,%s,%s,%s,%s,%s\n' \
          "$(date -Is)" "$PHASE" "$cpu" "${mem%% /*}" "${mem##*/ }" "$mempct" >> "$CSV"
      fi
      sleep "$SAMPLE_INTERVAL"
    done
  ) &
  SAMPLER_PID=$!
}

stop_sampler() {
  [[ -n "$SAMPLER_PID" ]] && kill "$SAMPLER_PID" 2>/dev/null && wait "$SAMPLER_PID" 2>/dev/null
  SAMPLER_PID=""
}

cleanup() {
  [[ -n "$SAMPLER_PID" ]] && kill "$SAMPLER_PID" 2>/dev/null
  [[ -n "$K6_PID" ]] && kill "$K6_PID" 2>/dev/null
  [[ -n "$ENVFILE_TMP" && -f "$ENVFILE_TMP" ]] && rm -f "$ENVFILE_TMP"
}
trap cleanup EXIT INT TERM

# ---------- storage helpers ----------
storage_stats() { # echoes "<count> <total_bytes>"
  local sizes
  sizes=$(aws s3api list-objects-v2 \
    --endpoint-url "$S3_ENDPOINT" --bucket "$S3_BUCKET" \
    ${S3_PREFIX:+--prefix "$S3_PREFIX"} \
    --output text --query 'Contents[].[Size]' 2>/dev/null) || return 1
  if [[ -z "$sizes" ]]; then
    echo "0 0"
  else
    echo "$(echo "$sizes" | wc -l) $(echo "$sizes" | awk '{s+=$1} END{print s+0}')"
  fi
}

drain() {
  if [[ $STORAGE_OK != 1 ]]; then
    info "storage unavailable — sleeping ${DRAIN_TIMEOUT}s as a fixed drain window"
    sleep "$DRAIN_TIMEOUT"
    return 0
  fi
  info "waiting for downstream drain (timeout ${DRAIN_TIMEOUT}s, stable x$DRAIN_STABLE @ ${DRAIN_POLL}s)..."
  local prev="-1" cur="-1" stable=0 elapsed=0
  while (( elapsed < DRAIN_TIMEOUT )); do
    cur=$(storage_stats | awk '{print $1}')
    if [[ "$cur" == "$prev" ]]; then
      stable=$((stable + 1))
    else
      stable=0
      info "  objects: $cur"
    fi
    prev="$cur"
    if (( stable >= DRAIN_STABLE )); then
      info "drained: object count stable at $cur"
      return 0
    fi
    sleep "$DRAIN_POLL"
    elapsed=$((elapsed + DRAIN_POLL))
  done
  info "WARNING: drain timeout (${DRAIN_TIMEOUT}s) — count still changing ($cur)"
}

# ---------- k6 runner ----------
# runs one scenario; sets global RUN_JSON to the report path, prints table
run_test() { # $1=name  $2=scenario-file  $3=result-glob-prefix
  local name="$1" scenario="$2" prefix="$3" rc newest
  say "Running $name test..."
  PHASE="$name"
  RUN_JSON=""
  k6 run -q scenarios/"$scenario" > "results/k6-$name-$STAMP.log" 2>&1 &
  K6_PID=$!
  wait "$K6_PID"
  rc=$?
  K6_PID=""
  if (( rc != 0 )); then
    info "WARNING: k6 exited non-zero ($rc) — see results/k6-$name-$STAMP.log"
  fi
  newest=$(ls -t results/"$prefix"-*.json 2>/dev/null | head -1 || true)
  [[ -z "$newest" ]] && die "no report produced for $name test"
  RUN_JSON="$newest"
  info "report: $newest"
  grep -E '^\| ' "results/k6-$name-$STAMP.log" | sed 's/^/    /'
  PHASE="between-tests"
}

ENVFILE_TMP=$(mktemp)

# =============================================================================
say "Ultimate benchmark starting"
info "target:      $TARGET_URL"
info "container:   $CONTAINER_NAME (monitoring: $([[ $DOCKER_OK = 1 ]] && echo yes || echo no))"
info "storage:     $([[ $STORAGE_OK = 1 ]] && echo "$S3_ENDPOINT / $S3_BUCKET" || echo 'not configured')"
info "results dir: $PWD/results"

start_sampler

# ---- storage baseline ----
BASELINE_COUNT=-1; BASELINE_BYTES=-1
AFTER_PROG=-1; AFTER_SUST=-1; FINAL_COUNT=-1; FINAL_BYTES=-1
if [[ $STORAGE_OK = 1 ]]; then
  say "Storage baseline"
  read -r BASELINE_COUNT BASELINE_BYTES <<< "$(storage_stats)"
  info "objects=$BASELINE_COUNT total_bytes=$BASELINE_BYTES"
fi

# ---- phase 1: progressive ----
run_test progressive progressive.js progressive-load-test; PROGRESSIVE_JSON="$RUN_JSON"; export PROGRESSIVE_JSON
drain
[[ $STORAGE_OK = 1 ]] && read -r AFTER_PROG _ <<< "$(storage_stats)"

# ---- phase 2: sustained ----
run_test sustained sustained.js sustained-load-test; SUSTAINED_JSON="$RUN_JSON"; export SUSTAINED_JSON
drain
[[ $STORAGE_OK = 1 ]] && read -r AFTER_SUST _ <<< "$(storage_stats)"

# ---- phase 3: burst ----
run_test burst burst.js burst-load-test; BURST_JSON="$RUN_JSON"; export BURST_JSON
drain

# ---- storage verification ----
MSGS_PERSISTED=-1; MSGS_OBJECTS=-1
if [[ $STORAGE_OK = 1 ]]; then
  say "Storage verification"
  read -r FINAL_COUNT FINAL_BYTES <<< "$(storage_stats)"
  info "objects=$FINAL_COUNT total_bytes=$FINAL_BYTES"
  if [[ -x scripts/count-stored-messages.sh ]]; then
    info "counting exact messages persisted since $START_UTC (downloads objects created during this run)..."
    if MSG_LINE=$(./scripts/count-stored-messages.sh "$START_UTC" 2>/dev/null); then
      MSGS_OBJECTS=$(echo "$MSG_LINE" | sed -n 's/.*objects=\([0-9]*\).*/\1/p')
      MSGS_PERSISTED=$(echo "$MSG_LINE" | sed -n 's/.*messages=\([0-9]*\).*/\1/p')
      info "messages persisted in new objects=$MSGS_PERSISTED (across $MSGS_OBJECTS objects)"
    else
      info "WARNING: message counting failed — see scripts/count-stored-messages.sh output"
    fi
  fi
fi

say "Stopping CPU/RAM monitoring"
stop_sampler

# ---- assemble the single results file ----
say "Writing $OUT_JSON"

export _PROGRESSIVE_JSON="$PROGRESSIVE_JSON" _SUSTAINED_JSON="$SUSTAINED_JSON" _BURST_JSON="$BURST_JSON"
export _TARGET_URL="$TARGET_URL" _CONTAINER_NAME="$CONTAINER_NAME" _CSV="$CSV" _STAMP="$STAMP"
export _BASELINE_COUNT="${BASELINE_COUNT:--1}" _BASELINE_BYTES="${BASELINE_BYTES:--1}"
export _AFTER_PROG="${AFTER_PROG:--1}" _AFTER_SUST="${AFTER_SUST:--1}"
export _FINAL_COUNT="${FINAL_COUNT:--1}" _FINAL_BYTES="${FINAL_BYTES:--1}"
export _STORAGE_OK _S3_BUCKET _START_UTC="$START_UTC"
export _MSGS_PERSISTED="${MSGS_PERSISTED:--1}" _MSGS_OBJECTS="${MSGS_OBJECTS:--1}"

python3 - "$OUT_JSON" <<'PYEOF'
import json, os, re, subprocess, sys
from datetime import datetime, timezone

out_path = sys.argv[1]
csv_path = os.environ['_CSV']

def load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return None

units = {'B': 1, 'KiB': 1024, 'MiB': 1024**2, 'GiB': 1024**3, 'TiB': 1024**4}

def to_bytes(s):
    m = re.match(r'([\d.]+)\s*(\w+)', str(s).strip())
    return float(m.group(1)) * units.get(m.group(2), 1) if m else None

def pct(s):
    m = re.match(r'([\d.]+)%', str(s).strip())
    return float(m.group(1)) if m else None

rows = []
try:
    with open(csv_path) as f:
        next(f)
        for line in f:
            parts = line.strip().split(',')
            if len(parts) >= 6:
                rows.append({'phase': parts[1], 'cpu_pct': pct(parts[2]),
                             'mem_used_b': to_bytes(parts[3])})
except FileNotFoundError:
    pass

def summarize(rs):
    if not rs:
        return None
    cpus = [r['cpu_pct'] for r in rs if r['cpu_pct'] is not None]
    mems = [r['mem_used_b'] for r in rs if r['mem_used_b'] is not None]
    return {
        'samples': len(rs),
        'avg_cpu_percent': round(sum(cpus) / len(cpus), 2) if cpus else None,
        'max_cpu_percent': round(max(cpus), 2) if cpus else None,
        'avg_mem_mib': round(sum(mems) / len(mems) / 1024**2, 2) if mems else None,
        'peak_mem_mib': round(max(mems) / 1024**2, 2) if mems else None,
    }

per_phase, overall = {}, summarize(rows)
for name in ('progressive', 'sustained', 'burst', 'between-tests', 'idle'):
    sub = summarize([r for r in rows if r['phase'] == name])
    if sub:
        per_phase[name] = sub

tests = {}
for name in ('progressive', 'sustained', 'burst'):
    rep = load(os.environ.get('_' + name.upper() + '_JSON'))
    tests[name] = rep
    # efficiency: avg cpu% over the test window normalized per 1000 events
    if rep and per_phase.get(name):
        ev = (rep.get('counters') or {}).get('events_sent') or 0
        dur_s = sum(int(re.match(r'(\d+)', st.get('stage', '')).group(1))
                    for st in rep.get('stages', [])
                    if re.match(r'(\d+)', st.get('stage', '')))
        if ev and dur_s and per_phase[name]['avg_cpu_percent'] is not None:
            per_phase[name]['avg_cpu_seconds_per_1000_events'] = round(
                per_phase[name]['avg_cpu_percent'] / 100 * dur_s / (ev / 1000), 4)

# sent vs persisted: events_sent summed across all test phases
messages_sent = sum(
    ((t or {}).get('counters') or {}).get('events_sent') or 0
    for t in tests.values()
)
def git_sha():
    try:
        return subprocess.check_output(
            ['git', 'rev-parse', '--short', 'HEAD'],
            cwd=os.path.dirname(os.path.abspath(out_path))).decode().strip()
    except Exception:
        return None

def env_int(name):
    try:
        return int(os.environ.get(name, '-1'))
    except (TypeError, ValueError):
        return -1

ok = os.environ.get('_STORAGE_OK') == '1'
result = {
    'benchmark': 'full',
    'generated_at_utc': datetime.now(timezone.utc).isoformat(),
    'git_sha': git_sha(),
    'target_url': os.environ['_TARGET_URL'],
    'resources': {
        'container': os.environ['_CONTAINER_NAME'],
        'monitored': bool(rows),
        'sample_interval_s': int(os.environ.get('SAMPLE_INTERVAL', '1')),
        'overall': overall,
        'per_phase': per_phase,
        'csv_file': os.path.basename(csv_path),
    },
    'storage': {
        'configured': ok,
        'bucket': os.environ.get('_S3_BUCKET'),
        'baseline_objects': env_int('_BASELINE_COUNT'),
        'after_progressive_objects': env_int('_AFTER_PROG'),
        'after_sustained_objects': env_int('_AFTER_SUST'),
        'final_objects': env_int('_FINAL_COUNT'),
        'baseline_total_bytes': env_int('_BASELINE_BYTES'),
        'final_total_bytes': env_int('_FINAL_BYTES'),
        'cutoff_utc': os.environ.get('_START_UTC'),
        'messages_persisted_exact': env_int('_MSGS_PERSISTED'),
        'messages_persisted_objects': env_int('_MSGS_OBJECTS'),
        'messages_sent_http': messages_sent,
        'persistence_ratio': (
            round(env_int('_MSGS_PERSISTED') / messages_sent, 6)
            if env_int('_MSGS_PERSISTED') >= 0 and messages_sent > 0 else None
        ),
        'note': ('messages_persisted_exact = exact per-message count obtained by '
                 'downloading every object created after cutoff_utc and counting '
                 'its records (JSONL, one message per line); batch sizes vary per '
                 'object so size-based estimates are not used'),
    },
    'tests': tests,
}
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2)
print(f'    wrote {out_path}')
PYEOF
RC_PY=$?

rm -f "$ENVFILE_TMP"
say "Done"
[[ $RC_PY = 0 ]] || die "failed to assemble combined report (individual reports are still in results/)"
info "combined : $OUT_JSON"
info "cpu/mem  : $CSV"
[[ -f results/k6-progressive-$STAMP.log ]] && info "raw logs  : results/k6-{progressive,sustained,burst}-$STAMP.log"
