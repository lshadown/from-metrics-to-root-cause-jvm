#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
RPS="${RPS:-2}"

# Fail-fast: verify api-service is reachable
if ! curl -fsS -o /dev/null "${BASE_URL}/orders?userId=41" 2>/dev/null; then
  echo "ERROR: api-service is not reachable at ${BASE_URL}. Start api-service and try again."
  exit 1
fi

SLEEP_INTERVAL=$(awk "BEGIN {printf \"%.4f\", 1/${RPS}}")

# Counters (use temp files so subshells can append)
STATS_DIR=$(mktemp -d)
trap 'rm -rf "${STATS_DIR}"; echo ""; echo "Stopped."; exit 0' INT TERM

echo "=== Baseline traffic generator ==="
echo "base=${BASE_URL}  rps=${RPS}  interval=${SLEEP_INTERVAL}s"
echo "Press Ctrl+C to stop."
echo ""

TOTAL=0
WINDOW_START=$(date +%s)
WINDOW_PREMIUM=0
WINDOW_STANDARD=0
WINDOW_COUNT=0
LATENCY_SUM=0

while true; do
  # Pick userId: 80% standard (41), 20% premium (40)
  RAND_USER=$(( RANDOM % 100 ))
  if (( RAND_USER < 20 )); then
    USER_ID=40
    USER_TYPE="premium"
  else
    USER_ID=41
    USER_TYPE="standard"
  fi

  # Pick details: 50/50
  RAND_DETAIL=$(( RANDOM % 2 ))
  if (( RAND_DETAIL == 0 )); then
    DETAILS="true"
  else
    DETAILS="false"
  fi

  URL="${BASE_URL}/orders?userId=${USER_ID}&details=${DETAILS}"

  # Fire request in background to not block the loop timing
  (
    LATENCY=$(curl -s -o /dev/null -w "%{time_total}" "${URL}" 2>/dev/null || echo "0")
    echo "${LATENCY} ${USER_TYPE}" >> "${STATS_DIR}/window.log"
  ) &

  TOTAL=$(( TOTAL + 1 ))

  # Print summary every 10 seconds
  NOW=$(date +%s)
  ELAPSED=$(( NOW - WINDOW_START ))
  if (( ELAPSED >= 10 )); then
    # Read accumulated stats from the window log
    W_COUNT=0
    W_PREMIUM=0
    W_STANDARD=0
    W_LATENCY_SUM=0
    if [[ -f "${STATS_DIR}/window.log" ]]; then
      while IFS=' ' read -r lat utype; do
        W_COUNT=$(( W_COUNT + 1 ))
        W_LATENCY_SUM=$(awk "BEGIN {printf \"%.6f\", ${W_LATENCY_SUM} + ${lat}}")
        if [[ "${utype}" == "premium" ]]; then
          W_PREMIUM=$(( W_PREMIUM + 1 ))
        else
          W_STANDARD=$(( W_STANDARD + 1 ))
        fi
      done < "${STATS_DIR}/window.log"
      rm -f "${STATS_DIR}/window.log"
    fi

    if (( W_COUNT > 0 )); then
      AVG=$(awk "BEGIN {printf \"%.3f\", ${W_LATENCY_SUM} / ${W_COUNT}}")
    else
      AVG="n/a"
    fi

    printf "[%s]  total=%d  window: reqs=%d  avg=%ss  premium=%d  standard=%d\n" \
      "$(date +%H:%M:%S)" "$TOTAL" "$W_COUNT" "$AVG" "$W_PREMIUM" "$W_STANDARD"

    WINDOW_START=$NOW
  fi

  sleep "${SLEEP_INTERVAL}"
done
