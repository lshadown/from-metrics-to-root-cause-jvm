#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://demo-a.gruzewski.dev}"
BASELINE_RPS="${BASELINE_RPS:-5}"
PARALLEL="${PARALLEL:-15}"
PREMIUM_USER_ID="${PREMIUM_USER_ID:-40}"
WAIT_FOR_TTL="${WAIT_FOR_TTL:-30}"

# ── Fail-fast ────────────────────────────────────────────────────────────────
if ! curl -fsS -o /dev/null "${BASE_URL}/orders?userId=41&details=true" 2>/dev/null; then
  echo "ERROR: api-service not reachable at ${BASE_URL}"
  exit 1
fi

STATS_DIR=$(mktemp -d)
trap 'rm -rf "${STATS_DIR}"; echo ""; echo "Stopped."; kill 0' INT TERM

echo "=== Demo traffic: baseline + cyclic premium contention ==="
echo "base=${BASE_URL}"
echo "baseline_rps=${BASELINE_RPS}  premium_parallel=${PARALLEL}  premium_userId=${PREMIUM_USER_ID}"
echo "Press Ctrl+C to stop."
echo ""

# ── Baseline traffic (background) ────────────────────────────────────────────
baseline_loop() {
  local sleep_interval
  sleep_interval=$(awk "BEGIN {printf \"%.4f\", 1/${BASELINE_RPS}}")

  while true; do
    local user_id=$(( (RANDOM % 600) * 2 + 1 ))   # odd = standard users only
    (
      curl -s -o /dev/null \
        "${BASE_URL}/orders?userId=${user_id}&details=true" 2>/dev/null || true
    ) &
    sleep "${sleep_interval}"
  done
}

baseline_loop &
BASELINE_PID=$!
echo "[baseline] Started (rps=${BASELINE_RPS}, standard users only, pid=${BASELINE_PID})"

# ── Warm premium cache once ───────────────────────────────────────────────────
echo "[premium]  Warming cache for userId=${PREMIUM_USER_ID}..."
curl -s -o /dev/null "${BASE_URL}/orders?userId=${PREMIUM_USER_ID}&details=true"
echo "[premium]  Cache warmed. First burst in ${WAIT_FOR_TTL}s..."
echo ""

# ── Cyclic premium contention (foreground) ───────────────────────────────────
ROUND=0
TOTAL_PREMIUM=0

while true; do
  sleep "${WAIT_FOR_TTL}"

  ROUND=$(( ROUND + 1 ))
  ROUND_DIR="${STATS_DIR}/round_${ROUND}"
  mkdir -p "${ROUND_DIR}"

  for i in $(seq 1 "${PARALLEL}"); do
    (
      LATENCY=$(curl -s -o /dev/null -w "%{time_total}" \
        "${BASE_URL}/orders?userId=${PREMIUM_USER_ID}&details=true" 2>/dev/null || echo "0")
      echo "${LATENCY}" >> "${ROUND_DIR}/results.log"
    ) &
  done
  # no wait — burst fires and we immediately sleep for next cycle

  TOTAL_PREMIUM=$(( TOTAL_PREMIUM + PARALLEL ))

  printf "[%s]  round=%d  premium_total=%d  burst fired (parallel=%d)\n" \
    "$(date +%H:%M:%S)" "$ROUND" "$TOTAL_PREMIUM" "$PARALLEL"
done