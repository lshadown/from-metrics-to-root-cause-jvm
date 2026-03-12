#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://demo-a.gruzewski.dev}"
RPS="${RPS:-20}"

# Fail-fast: verify api-service is reachable
if ! curl -fsS -o /dev/null "${BASE_URL}/orders?userId=41" 2>/dev/null; then
  echo "ERROR: api-service is not reachable at ${BASE_URL}. Start api-service and try again."
  exit 1
fi

SLEEP_INTERVAL=$(awk "BEGIN {printf \"%.4f\", 1/${RPS}}")

STATS_DIR=$(mktemp -d)
trap 'rm -rf "${STATS_DIR}"; echo ""; echo "Stopped."; exit 0' INT TERM

echo "=== Baseline traffic generator ==="
echo "base=${BASE_URL}  rps=${RPS}  interval=${SLEEP_INTERVAL}s"
echo "Standard users only (userId=41, details=false)"
echo "Press Ctrl+C to stop."
echo ""

TOTAL=0
WINDOW_START=$(date +%s)


while true; do
  USER_ID=$(( (RANDOM % 600) * 2 + 1 ))
  URL="${BASE_URL}/orders?userId=${USER_ID}&details=true"

  (
    LATENCY=$(curl -s -o /dev/null -w "%{time_total}" "${URL}" 2>/dev/null || echo "0")
    echo "${LATENCY}" >> "${STATS_DIR}/window.log"
  ) &

  TOTAL=$(( TOTAL + 1 ))

  NOW=$(date +%s)
  ELAPSED=$(( NOW - WINDOW_START ))
  if (( ELAPSED >= 10 )); then
    W_COUNT=0
    W_LATENCY_SUM=0
    if [[ -f "${STATS_DIR}/window.log" ]]; then
      while IFS=' ' read -r lat; do
        W_COUNT=$(( W_COUNT + 1 ))
        W_LATENCY_SUM=$(awk "BEGIN {printf \"%.6f\", ${W_LATENCY_SUM} + ${lat}}")
      done < "${STATS_DIR}/window.log"
      rm -f "${STATS_DIR}/window.log"
    fi

    if (( W_COUNT > 0 )); then
      AVG=$(awk "BEGIN {printf \"%.3f\", ${W_LATENCY_SUM} / ${W_COUNT}}")
    else
      AVG="n/a"
    fi

    printf "[%s]  total=%d  window: reqs=%d  avg=%ss\n" \
      "$(date +%H:%M:%S)" "$TOTAL" "$W_COUNT" "$AVG"

    WINDOW_START=$NOW
  fi

  sleep "${SLEEP_INTERVAL}"
done