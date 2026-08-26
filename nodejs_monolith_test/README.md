# nodejs_monolith_test — naive baseline

Deliberately dumb Node.js ingestion service used as a benchmark baseline
against the optimized Go/Kafka/Redpanda-Connect stack.

- **Express** HTTP server, one route: `POST /events/ingest` (JWT HS256 bearer auth)
- Per event: validate required fields → **one synchronous S3 PUT** (`<uuid>.json`, single JSON line)
- No batching, no compression, no queue/buffer, no optimizations of any kind

## Layout

```
ingestion-service/
├── Dockerfile
├── package.json
└── src/
    ├── index.js            # entrypoint: listen on PORT
    ├── app.js              # express app + route mounting
    ├── config/index.js     # env config
    ├── lib/jwt.js          # hand-rolled HS256 verification
    ├── middleware/auth.js  # bearer-token middleware
    ├── routes/health.js    # GET /health
    ├── routes/events.js    # POST /events/ingest
    ├── services/s3.js      # per-event S3 PUT (the naive part)
    └── utils/validate.js   # event field validation
```

## Stack

| service | image | notes |
|---|---|---|
| `ingestion-node-monolith` | built from `./node` | Express app, port `8080` |
| `s3-storage-node` | `chrislusf/seaweedfs` | S3 endpoint on `8333`, UI on `8888`, fresh volume |
| `s3-init` | `amazon/aws-cli` | waits for SeaweedFS + creates the bucket |

## Run

```sh
cd nodejs_monolith_test
docker compose up -d --build
curl http://localhost:8080/health   # -> "All good"
```

## Stress test

Same contract as the Go service, so the existing `stress-test/` works
unmodified — same ports (8080 / 8333), same JWT secret, same bucket.
Just override the container name for CPU/RAM sampling:

```sh
cd ../stress-test
CONTAINER_NAME=ingestion-node-monolith ./scripts/run-full-benchmark.sh
```

Storage verification (`verify-storage.sh`, `count-stored-messages.sh`)
works as-is: each event is exactly one line in exactly one object, so the
exact message count equals the object count.

> Note: don't run this stack and the main stack at the same time — they
> share host ports 8080/8333/8888.

## Config

See `.env` (copy `.env.example`). Keys: `PORT`, `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `S3_BUCKET`, `S3_ENDPOINT`, `JWT_SECRET`.
