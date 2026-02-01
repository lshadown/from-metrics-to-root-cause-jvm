#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREMIUM_USER_ID="${PREMIUM_USER_ID:-40}"
STANDARD_USER_ID="${STANDARD_USER_ID:-41}"
CONCURRENCY="${CONCURRENCY:-10}"
BASE_URL="${BASE_URL:-http://localhost:8080}"
TTL_WAIT="${TTL_WAIT:-6}"

# Fail-fast: verify api-service is reachable
if ! curl -fsS -o /dev/null "${BASE_URL}/orders?userId=41" 2>/dev/null; then
  echo "ERROR: api-service is not reachable at ${BASE_URL}. Start api-service and try again."
  exit 1
fi

echo "============================================"
echo " Premium vs Standard comparison"
echo " premium=${PREMIUM_USER_ID}  standard=${STANDARD_USER_ID}"
echo " concurrency=${CONCURRENCY}  base=${BASE_URL}"
echo "============================================"
echo ""

echo ">>> PREMIUM (userId=${PREMIUM_USER_ID}): contention expected"
echo "--------------------------------------------"
USER_ID="${PREMIUM_USER_ID}" \
CONCURRENCY="${CONCURRENCY}" \
BASE_URL="${BASE_URL}" \
TTL_WAIT="${TTL_WAIT}" \
  "${SCRIPT_DIR}/trigger-premium-contention.sh"

echo ""
echo ">>> STANDARD (userId=${STANDARD_USER_ID}): should remain stable"
echo "--------------------------------------------"

STANDARD_URL="${BASE_URL}/orders?userId=${STANDARD_USER_ID}&details=true"

echo "1) Warming cache..."
curl -s -o /dev/null -w "   warm-up: %{time_total}s\n" "${STANDARD_URL}"

echo "2) Firing ${CONCURRENCY} concurrent requests (cache should be warm, TTL=60s)..."
for i in $(seq 1 "${CONCURRENCY}"); do
  (
    duration=$(curl -s -o /dev/null -w "%{time_total}" "${STANDARD_URL}")
    printf "   req=%2d  time=%ss\n" "$i" "$duration"
  ) &
done
wait

echo ""
echo "Done."
echo ""
echo "============================================"
echo " Premium: contention expected (~2.5s+ per request)"
echo " Standard: should remain stable (fast, <100ms)"
echo "============================================"
