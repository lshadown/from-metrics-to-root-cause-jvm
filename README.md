# metrics-to-root-cause-jvm

Demo project: from metrics to root cause in a JVM microservice setup.

## Services

| Service | Port | Description |
|---|---|---|
| api-service | 8080 | Main API with `/orders` endpoint, enrichment cache with per-user locking |
| external-service | 8081 | Downstream enrichment service with deterministic latency |

## Quick start (Docker)

```bash
docker-compose up --build
```

This starts both services. Verify with:

```bash
curl "http://localhost:8081/enrichment?userId=40"
curl "http://localhost:8080/orders?userId=40&details=true"
```

Stop everything:

```bash
docker-compose down
```

## Load test scripts

All scripts require api-service (port 8080) and external-service (port 8081) to be running. They fail fast with a clear error if api-service is not reachable.

### Continuous baseline traffic

Generates steady mixed traffic (80% standard, 20% premium, 50% with details). Prints a summary every 10 seconds. Runs until Ctrl+C.

```bash
./scripts/baseline-traffic.sh
```

Override the request rate:

```bash
RPS=5 ./scripts/baseline-traffic.sh
```

### Burst scripts

Trigger premium lock contention (waits 6s for TTL expiry, then fires concurrent requests):

```bash
./scripts/trigger-premium-contention.sh
```

Compare premium vs standard behavior side by side:

```bash
./scripts/compare-premium-vs-standard.sh
```

### Environment variables

| Variable | Default | Used by |
|---|---|---|
| `BASE_URL` | `http://localhost:8080` | all |
| `RPS` | `2` | baseline-traffic |
| `CONCURRENCY` | `10` | burst scripts |
| `USER_ID` | `40` | trigger-premium-contention |
| `TTL_WAIT` | `6` | both |
| `PREMIUM_USER_ID` | `40` | compare-premium-vs-standard |
| `STANDARD_USER_ID` | `41` | compare-premium-vs-standard |

Example with overrides:

```bash
CONCURRENCY=20 ./scripts/trigger-premium-contention.sh
```

Premium users (`userId % 20 == 0`) have a 5s cache TTL. The script sleeps 6s to force expiry, then fires concurrent requests that contend on the per-user lock while one thread refreshes from external-service (~2.5s). Standard users have a 60s TTL and remain fast after warm-up.
