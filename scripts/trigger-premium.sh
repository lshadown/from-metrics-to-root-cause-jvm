#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://demo-a.gruzewski.dev}"
PARALLEL="${PARALLEL:-10}"
WAIT_FOR_TTL="${WAIT_FOR_TTL:-6}"

if ! curl -fsS -o /dev/null "${BASE_URL}/orders?userId=40&details=true" 2>/dev/null; then
  echo "ERROR: api-service is not reachable at ${BASE_URL}. Start api-service and try again."
  exit 1
fi

STATS_DIR=$(mktemp -d)
trap 'rm -rf "${STATS_DIR}"; echo ""; echo "Stopped."; exit 0' INT TERM

echo "=== Premium contention trigger (continuous) ==="
echo "base=${BASE_URL}  parallel=${PARALLEL}  userId=40 (premium)"
echo "Press Ctrl+C to stop."
echo ""

echo "[1/2] Warming up cache for userId=40..."
curl -s -o /dev/null "${BASE_URL}/orders?userId=40&details=true"
echo "      Cache warmed."
echo ""

echo "[2/2] Waiting ${WAIT_FOR_TTL}s for premium cache TTL to expire..."
sleep "${WAIT_FOR_TTL}"
echo "      TTL expired. Starting continuous contention..."
echo ""

ROUND=0
TOTAL=0

while true; do
  ROUND=$(( ROUND + 1 ))
  ROUND_DIR="${STATS_DIR}/round_${ROUND}"
  mkdir -p "${ROUND_DIR}"

  for i in $(seq 1 "${PARALLEL}"); do
    (
      LATENCY=$(curl -s -o /dev/null -w "%{time_total}" \
        "${BASE_URL}/orders?userId=40&details=true" 2>/dev/null || echo "0")
      echo "${LATENCY}" >> "${ROUND_DIR}/results.log"
    ) &
  done

  wait

  TOTAL=$(( TOTAL + PARALLEL ))

  COUNT=0
  SUM=0
  MAX=0
  if [[ -f "${ROUND_DIR}/results.log" ]]; then
    while read -r lat; do
      COUNT=$(( COUNT + 1 ))
      SUM=$(awk "BEGIN {printf \"%.6f\", ${SUM} + ${lat}}")
      MAX=$(awk "BEGIN {if (${lat} > ${MAX}) printf \"%.6f\", ${lat}; else printf \"%.6f\", ${MAX}}")
    done < "${ROUND_DIR}/results.log"
    rm -rf "${ROUND_DIR}"
  fi

  if (( COUNT > 0 )); then
    AVG=$(awk "BEGIN {printf \"%.3f\", ${SUM} / ${COUNT}}")
    printf "[%s]  round=%d  total=%d  avg=%ss  max=%ss\n" \
      "$(date +%H:%M:%S)" "$ROUND" "$TOTAL" "$AVG" "$MAX"
  fi

  sleep "${WAIT_FOR_TTL}"
done