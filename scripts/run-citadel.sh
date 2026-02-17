#!/usr/bin/env bash

# Start Citadel OSS HTTP sidecar (citadel serve) and wait until it's healthy.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PORT="${CITADEL_PORT:-8787}"
BASE_URL="http://127.0.0.1:${PORT}"

DEFAULT_BIN="${ROOT_DIR}/bin/citadel"
BIN="${CITADEL_BIN:-${DEFAULT_BIN}}"

if [[ -x "${BIN}" ]]; then
  : # ok
elif command -v citadel >/dev/null 2>&1; then
  BIN="$(command -v citadel)"
else
  echo "Citadel binary not found." >&2
  echo "Expected executable at: ${DEFAULT_BIN}" >&2
  echo "Or set CITADEL_BIN=/path/to/citadel, or install citadel in PATH." >&2
  echo "" >&2
  echo "Run ./scripts/setup.sh for build instructions." >&2
  exit 1
fi

LOG_DIR="${ROOT_DIR}/.citadel"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/citadel.log"

echo "Starting Citadel: ${BIN} serve ${PORT}" >&2
"${BIN}" serve "${PORT}" >"${LOG_FILE}" 2>&1 &
SERVER_PID="$!"

cleanup() {
  if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

deadline=$((SECONDS + 20))
ready=0
while ((SECONDS < deadline)); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/health" 2>/dev/null || true)"
  if [[ "${code}" == "200" ]]; then
    ready=1
    break
  fi

  code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/" 2>/dev/null || true)"
  if [[ "${code}" == "200" ]]; then
    ready=1
    break
  fi

  sleep 1
done

if [[ "${ready}" != "1" ]]; then
  echo "Citadel failed to become healthy within 20s at ${BASE_URL}." >&2
  echo "Last logs (${LOG_FILE}):" >&2
  tail -n 80 "${LOG_FILE}" >&2 || true
  exit 1
fi

echo "Citadel ready: ${BASE_URL}" >&2
echo "Logs: ${LOG_FILE}" >&2

wait "${SERVER_PID}"

