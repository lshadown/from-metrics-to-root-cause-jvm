# external-service

Downstream service that simulates deterministic latency for user enrichment lookups.

## Running locally

```bash
cd external-service
./mvnw spring-boot:run
```

Or build and run as a JAR:

```bash
cd external-service
./mvnw package -DskipTests
java -jar target/external-service-0.0.1-SNAPSHOT.jar
```

The service starts on port **8081** by default.

## Example requests

Slow path (~2.5s) — user divisible by 20 gets `premium` segment:

```bash
curl "http://localhost:8081/enrichment?userId=40"
# {"userId":40,"segment":"premium","riskScore":65}
```

Fast path (~80ms) — all other users get `standard` segment:

```bash
curl "http://localhost:8081/enrichment?userId=41"
# {"userId":41,"segment":"standard","riskScore":78}
```
