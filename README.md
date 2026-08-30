# High-Performance Event Ingestor

A high-throughput, fault-tolerant system for ingesting event data from clients to durable S3-compatible storage via Kafka/Redpanda and Redpanda Connect as a sink connector.

## Architecture Overview

```
Client → Go HTTP Server (JWT-authenticated) → Kafka (Redpanda) → Redpanda Connect Sink → Object Storage
```

## Directory Structure

```
high-perf-data-ingestor/
├── .env, .env.dev, .env.example          # Environment configuration
├── docker-compose.yml                      # Production docker orchestration
├── docker-compose.dev.yml                  # Development docker orchestration
├── redpanda-connect-config.yaml          # Redpanda Connect sink configuration
├── ingestion-service/                      # Go backend service
│   ├── cmd/server/main.go                 # Entry point
│   ├── go.mod, go.sum                     # Dependencies
│   ├── internal/                          # Internal packages
│   │   ├── api/                           # HTTP API (chi router + JWT)
│   │   ├── env/                           # Environment variable helpers
│   │   ├── events/                        # Event service & handler
│   │   │   ├── types.go                   # Event struct
│   │   │   ├── service.go                 # Kafka write logic with backpressure
│   │   │   └── handler.go                 # HTTP POST /events/ingest handler
│   │   ├── json_utils/                    # High-performance JSON parsing
│   │   ├── kafka_utils/                   # Custom Kafka writer with backpressure, batching, DLQ
│   │   └── jwt/                           # JWT HS256 middleware
│   ├── Dockerfile, Dockerfile.dev          # Build containers
│   └── tmp/                               # Build artifacts
├── stress-test/                            # Benchmark/load test suite
│   ├── lib/                               # k6 scenario logic
│   ├── scenarios/                         # Sustained, progressive, burst test scripts
│   ├── scripts/                           # JWT generation, metric collection, storage verification
│   ├── .env.example                       # Stress test config
│   └── results/                           # Test output directory
└── nodejs_monolith/                        # Naive Node.js monolith baseline (reference only)
```

## Data Flow

Client → HTTPS POST /events/ingest (Go HTTP server) → JWT Authentication → JSON Parsing → Kafka Writer → Redpanda Connect Sink → Object Storage

## Components

### 1. Producer (Go Service)

**HTTP API:**
- `POST /events/ingest` - Protected by JWT bearer authentication
- `GET /health` - Health check endpoint

**Key Features:**
- **Backpressure**: Bounded queue (go channel) provides flow control. When full, returns HTTP 429 with `Retry-After: 1`
- **Batching**: Messages batched before writing to Kafka
- **Concurrent Writes**: Multiple drain goroutines for parallel Kafka writes
- **DLQ**: Failed messages routed to dead letter queue after max retries
- **JWT Authentication** middleware via go-chi

**Kafka Configuration:**
- Brokers: `redpanda-0:9092`
- Auto topic creation enabled
- Max retry attempts configured
- Write timeout per operation
- Batching parameters control message throughput

### 2. Kafka / Redpanda

- Redpanda cluster running `v26.2.1`
- Kafka API and schema registry configured for internal/external access
- Main topic `events` with auto-creation
- DLQ topic `events.dlq` for failed messages
- Consumer group `s3-storage-sink-connector` used by the sink connector

### 3. Redpanda Connect Sink Connector

- Reads from Kafka `events` topic
- Pipeline processes messages for batching and format conversion
- Outputs to S3-compatible object storage
- Batch configuration amortizes write operations

### 4. Object Storage

- S3-compatible endpoint configured via environment variables
- Bucket and credentials from `.env`

## Improvements Over a Simple Node.js Monolith

The previous Node.js monolith baseline maxed out at ~2,000 events/second, while this current architecture sustains ~28,000 events/second — roughly **14x higher throughput**.

| Area | Node.js Monolith | Go System | Improvement |
|---|---|---|---|
| **Messaging** | Direct S3 PUT per event | Kafka backpressure + batching | Buffering, decoupling, retries |
| **Throughput** | ~2k events/second max | ~28k events/second sustained | ~14x higher throughput; ~1000x fewer S3 writes |
| **Compression** | None | Compressed batched writes | Smaller storage footprint |
| **Flow Control** | None - writes proceed regardless | Bounded queue + 429 backpressure | Prevents data loss, controlled load |
| **Reliability** | One-shot PUT - no DLQ | Kafka + DLQ + retries | Failed messages routed to DLQ |
| **Concurrency** | Single-threaded request handling | Multiple drain goroutines | Parallelism |

## Key Deliberate Design Choices

1. **Kafka as a Buffer/Backplane**: Events flow through Kafka instead of direct S3 writes, providing:
   - Decoupling between producer and consumer rates
   - Natural buffering for traffic spikes
   - Ability to replay events if needed

2. **Bounded Queue with Backpressure**: The internal queue with HTTP 429 responses prevents:
   - Overwhelming Kafka during traffic spikes (queue fills up naturally as messages are not consumed fast enough. On full queue, returns HTTP 429)
   - Memory exhaustion
   - Silent data loss

3. **Batching at Multiple Levels**: 
   - Producer batches before writing to Kafka
   - Redpanda Connect batches before writing to storage
   - This amortizes write operations dramatically

4. **Compression**: Batched data is compressed before storage, reducing costs significantly

5. **Dead Letter Queue**: Failed messages after retries are routed to `events.dlq` for manual inspection

6. **Explicit Async Control**: The Go producer uses `Async: false` with explicit batching/drain control, giving full control over write semantics

7. **High-Performance JSON**: Sonic library used for JSON parsing/serialization

## Stress Testing

The project includes a k6-based stress test suite in `stress-test/`:

### Test Scenarios
1. **Sustained**: Constant rate for a duration
2. **Progressive**: Staged ramp of event rates
3. **Burst**: Baseline → high burst → recovery

### Configuration
All parameters are environment-variable driven. Copy `stress-test/.env.example` to `stress-test/.env` and adjust as needed.

### Running Stress Tests (Check README.md for more details)
> **Prefer running the stress tests from the `stress-test/` directory for proper result persistence**
```bash
# Generate JWT
export JWT_TOKEN=$(./scripts/generate-jwt.sh "<jwt_secret>" 3600)

# Sustained test
JWT_TOKEN="$JWT_TOKEN" k6 run scenarios/sustained.js

# Progressive test
JWT_TOKEN="$JWT_TOKEN" STAGES='1000:30s,5000:30s,...' k6 run scenarios/progressive.js

# Burst test
JWT_TOKEN="$JWT_TOKEN" BASELINE_RATE=1000 BASELINE_DURATION=30s BURST_RATE=20000 BURST_DURATION=10s RECOVERY_DURATION=60s k6 run scenarios/burst.js
```
### Verification
- **Object-level**: `./scripts/verify-storage.sh` - snapshot object count, sizes
- **Message-level**: `./scripts/count-stored-messages.sh <cutoff>` - exact per-message count by downloading objects created after a UTC cutoff and counting records (gzip-aware)

**Events sent vs persisted:**
1. Note UTC time before test
2. Run test; wait for drain
3. `count-stored-messages.sh <start-time>` → exact persisted count
4. Compare against `events_sent` / `events_accepted` from k6 report

### Full Benchmark (performs all tests in one)
```bash
./scripts/run-full-benchmark.sh
```
Runs progressive → sustained → burst tests, collects CPU/memory metrics, takes storage baselines, and produces a combined JSON report with exact message persistence counts.


## Development

### Local Development
```bash
docker-compose --env-file .env up -d
```
Starts ingestion-service, Redpanda, console, sink-connector, and SeaweedFS.

### Development Mode (hot-reload)
```bash
docker-compose -f docker-compose.dev --env-file .env.dev up -d
```
Uses `Dockerfile.dev` with `air` for automatic restart on code changes.

### Environment Variables
Copy `.env` or `.env.dev` and modify as needed:
- `PORT`, `QUEUE_SIZE` - ingestion service
- `BROKERS`, `KAFKA_EVENTS_TOPIC` - Kafka configuration
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_BUCKET`, `S3_ENDPOINT` - object storage
- `JWT_SECRET` - authentication

### API Usage
```bash
# Generate JWT token
export JWT_TOKEN=$(./scripts/generate-jwt.sh "secret" 3600)

# Send event
curl -X POST http://localhost:8080/events/ingest \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"eventId":"test-001","eventType":"click","timestamp":"2024-01-01T00:00:00Z","userId":"user-1",...}'
```
