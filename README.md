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