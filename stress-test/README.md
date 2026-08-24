# Stress-Test Suite

Standalone load/stress-testing setup for the event ingestion HTTP API.
**Fully isolated**: lives in this directory only, communicates with the
service exclusively over HTTP, and shares zero code with the application.

- Load generator: [k6](https://k6.io) (Grafana k6)
- Backend-agnostic: the generator assumes nothing but `POST <url>` with a
  Bearer token and a JSON body. Kafka/Redpanda, S3, Docker, etc. are only
  touched by *separate* helper scripts you run yourself.

---

## 1. Directory structure

```
stress-test/
├── README.md                            <- you are here
├── .env.example                         <- copy to .env, fill in values
├── lib/
│   ├── config.js                        <- all env-var config in one place
│   ├── event.js                         <- THE single event payload template (edit here)
│   ├── http.js                          <- shared request logic + counters
│   ├── options.js                       <- k6 scenario/threshold plumbing
│   └── report.js                        <- per-stage summary + JSON results writer
├── scenarios/
│   ├── sustained.js                     <- constant rate for a duration
│   ├── progressive.js                   <- staged ramp: 1k -> 5k -> ... -> Nk eps
│   └── burst.js                         <- baseline -> burst -> recovery
├── scripts/
│   ├── generate-jwt.sh                  <- mint an HS256 JWT (no deps beyond openssl)
│   ├── collect-container-metrics.sh     <- sample container CPU/mem to CSV
│   └── verify-storage.sh                <- count objects + sizes on S3-compatible storage
└── results/                             <- JSON reports + CSV metrics land here (gitignored)
```

## 2. What it measures

### From the load generator (k6)

| Metric | Meaning |
|---|---|
| **Achieved throughput (eps)** | Requests actually completed per second in a stage vs the target rate. |
| **Total requests** | All HTTP requests sent in a stage / test. |
| **p95 latency** | 95% of requests completed faster than this (ms). Tail indicator. |
| **p99 latency** | 99% of requests completed faster than this (ms). The number users feel at the worst; watch for instability across stages. |
| **Error rate** | % of requests that were not 2xx or failed at network level (`http_req_failed` + status-class counters). |
| **Status distribution** | Counts of 2xx / 3xx / 4xx / 5xx / network errors per stage. |
| **events_sent** | Total events handed to the HTTP client. |
| **events_accepted** | Events that got a 2xx response. |

> **Important:** `events_accepted` counts *API acceptance* only. Because the
> service produces asynchronously, a 202 does **not** mean persisted.
> Delivery/persistence is verified externally — see "Events sent vs
> persisted" below.

### Collected separately from infrastructure

| Metric | How |
|---|---|
| Container CPU/memory | `scripts/collect-container-metrics.sh` (docker stats sampler -> CSV) |
| Peak consumer lag | Lag inspection CLI of your broker (see §8) |
| Events persisted | Object-count delta on storage (see §9, `scripts/verify-storage.sh`) |
| Storage object sizes | Same script prints total + average object size |

## 3. Configuration / environment variables

Copy `.env.example` to `.env` and edit, or pass `-e VAR=value` per run.

| Variable | Default | Used by | Purpose |
|---|---|---|---|
| `TARGET_URL` | `http://localhost:8080/events/ingest` | all scenarios | Endpoint under test |
| `JWT_TOKEN` | *(required)* | all scenarios | Bearer token sent with every request |
| `RATE` | `1000` | sustained | Constant events/sec |
| `DURATION` | `60s` | sustained | Test length |
| `STAGES` | `1000:30s,5000:30s,10000:30s,15000:30s,20000:30s` | progressive | Comma-separated `rate:duration` stages |
| `BASELINE_RATE` / `BASELINE_DURATION` | `1000` / `30s` | burst | Pre-burst normal load |
| `BURST_RATE` / `BURST_DURATION` | `20000` / `10s` | burst | Burst intensity |
| `RECOVERY_DURATION` | `60s` | burst | Post-burst observation window |
| `MAX_VUS` | `500` | all | Cap on virtual users (raise if server latency grows) |
| `ERROR_RATE_THRESHOLD` | `1` (%) | flagging | Stage flagged if error rate exceeds this |
| `P99_SPIKE_FACTOR` | `2` | flagging | Stage flagged if p99 > factor × first stage's p99 |
| `THROUGHPUT_TOLERANCE` | `0.95` | flagging | Stage flagged if achieved < target × this |

Event payload is configured in exactly one place: `lib/event.js`
(`EVENT_TEMPLATE`). One representative event shape is used everywhere;
only `eventId`/`sessionId`/`timestamp` vary per iteration.

## 4. Install & run

```bash
# Arch Linux
sudo pacman -S k6          # or: https://grafana.com/docs/k6/latest/set-up/install-k6/
# macOS
brew install k6

# Helper scripts need: bash, openssl, docker CLI, aws CLI (storage check only)
```

All commands below are run from inside `stress-test/`.

## 5. Generate the JWT

```bash
export JWT_TOKEN=$(./scripts/generate-jwt.sh "<your JWT_SECRET>" 3600)
```

- `<your JWT_SECRET>` must match the secret the service validates against
  (in this repo: `JWT_SECRET` from `.env.dev`). Never hardcode it anywhere;
  it only ever lives in your shell env.
- `3600` = token TTL in seconds.
- Optional third arg sets the `userId` claim.

The script mints an HS256 token using plain `openssl`, no extra dependencies.

## 6. Running each test

```bash
cd stress-test

# --- Sustained baseline (default 1000 eps for 60s) -------------------
JWT_TOKEN="$JWT_TOKEN" k6 run scenarios/sustained.js
# custom:
JWT_TOKEN="$JWT_TOKEN" RATE=2000 DURATION=2m k6 run scenarios/sustained.js

# --- Progressive staged ramp ----------------------------------------
JWT_TOKEN="$JWT_TOKEN" \
  STAGES='1000:30s,5000:30s,10000:30s,15000:30s,20000:30s' \
  k6 run scenarios/progressive.js

# --- Burst test ------------------------------------------------------
JWT_TOKEN="$JWT_TOKEN" \
  BASELINE_RATE=1000 BASELINE_DURATION=30s \
  BURST_RATE=20000 BURST_DURATION=10s \
  RECOVERY_DURATION=60s \
  k6 run scenarios/burst.js
```

Or keep everything in `.env` and source it before running:

```bash
set -a; source .env; set +a
k6 run scenarios/<x>.js   # picks up all vars from .env
```

Each run prints a per-stage markdown table (achieved eps, p95, p99,
error rate, flags) and writes a structured JSON report to `results/`.
A stage is **flagged** (not aborted) when throughput can't be sustained,
errors exceed the threshold, or p99 spikes relative to the first stage —
so you always get the full picture.

Recommended workflow per benchmark session:

```bash
# terminal 1: resource sampling (start before, stop after the test)
CONTAINER_NAME=ingestion-service ./scripts/collect-container-metrics.sh

# terminal 2: pre-test persistence snapshot
./scripts/verify-storage.sh

# terminal 3: the actual test
k6 run scenarios/progressive.js

# afterwards: wait for drain, then re-check lag + storage
```

## 7. CPU / memory collection (separate from the generator)

```bash
./scripts/collect-container-metrics.sh                 # -> results/container-metrics-<ts>.csv
CONTAINER_NAME=redpanda-0 ./scripts/collect-container-metrics.sh out/rp.csv
```

One-shot peek: `docker stats --no-stream ingestion-service`.
The sampler works for any container name — it knows nothing about the app.

## 8. Inspecting consumer lag (separate)

Use your broker's own CLI/console — examples for Redpanda:

```bash
# consumer group offsets / lag for the sink group
docker exec redpanda-0 rpk group describe s3-storage-sink-connector

# watch during/after a burst until committed offsets catch up
watch -n 2 'docker exec redpanda-0 rpk group describe s3-storage-sink-connector'
```

For peak lag: start a watcher right before the burst test and let it run
through recovery; the max `LAG` column value observed is your peak lag.
(The Redpanda console UI on port 9080 shows the same graphically.)

With any other broker, use its equivalent consumer-group lag tooling —
the load generator itself never touches the broker.

## 9. Verifying events reached storage

```bash
./scripts/verify-storage.sh            # snapshot: object count, total & avg size
./scripts/verify-storage.sh --watch 5  # poll every 5s while the pipeline drains
```

**Events sent vs persisted:**

1. Snapshot before the test → baseline object count `B`.
2. Run the test; keep watching until new-object growth stops (drained).
3. Snapshot after → `A`. New objects = `A - B`; multiply by your sink's
   batch size (events per object) to compare against `events_accepted`,
   e.g. batches of 1000 events/object → `persisted ≈ (A-B) × 1000`.

Any shortfall between `events_accepted` and estimated persisted events =
downstream delivery/persistence loss (invisible to the HTTP layer).

## 10. Interpreting a run

- **Stage flagged "throughput shortfall"** → server saturated; find the last
  good stage — that's your current sustained ceiling.
- **p99 climbing much faster than p95 across stages** → tail-latency
  instability (GC pauses, queueing, lock contention).
- **Errors rising with load** → usually saturation (timeouts/5xx) rather
  than bad requests; correlate with the CPU/mem CSV.
- **Burst test**: if 202s stay high during the burst but lag spikes and then
  drains to ~0 within the recovery window, buffering/backpressure works as
  designed. If lag never drains, downstream is the bottleneck.
- **accepted ≫ persisted estimate** → async producer or sink dropping data.

Results in `results/*.json` are flat, timestamped, per-stage structures —
a future Prometheus/Grafana integration can read them without any rewrite
of the test code.

## Notes & gotchas

- Run k6 from inside `stress-test/` so `results/...` paths resolve.
- If high stages fail with "insufficient VUs", raise `MAX_VUS`.
- k6 v1.x: pass config via `-e VAR=...`, or real env vars (e.g. `set -a; source .env; set +a`).
