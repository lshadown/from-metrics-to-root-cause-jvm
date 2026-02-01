#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USER_ID="${USER_ID:-40}"
CONCURRENCY="${CONCURRENCY:-10}"
BASE_URL="${BASE_URL:-http://localhost:8080}"
TTL_WAIT="${TTL_WAIT:-6}"

# Fail-fast: verify api-service is reachable
if ! curl -fsS -o /dev/null "${BASE_URL}/orders?userId=41" 2>/dev/null; then
  echo "ERROR: api-service is not reachable at ${BASE_URL}. Start api-service and try again."
  exit 1
fi

URL="${BASE_URL}/orders?userId=${USER_ID}&details=true"

echo "=== Premium contention trigger ==="
echo "userId=${USER_ID}  concurrency=${CONCURRENCY}  base=${BASE_URL}"
echo ""

echo "1) Warming cache..."
curl -s -o /dev/null -w "   warm-up: %{time_total}s\n" "${URL}"

echo "2) Sleeping ${TTL_WAIT}s to expire premium TTL..."
sleep "${TTL_WAIT}"

echo "3) Firing ${CONCURRENCY} concurrent requests..."
for i in $(seq 1 "${CONCURRENCY}"); do
  (
    duration=$(curl -s -o /dev/null -w "%{time_total}" "${URL}")
    printf "   req=%2d  time=%ss\n" "$i" "$duration"
  ) &
done
wait

echo ""
echo "Done."
