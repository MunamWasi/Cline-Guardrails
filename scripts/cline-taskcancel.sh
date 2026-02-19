#!/usr/bin/env bash

# Cline TaskCancel hook for Mighty Guardrails temp cleanup.
# Prints nothing by design.

set -euo pipefail

stdin_json="$(cat 2>/dev/null || true)"

sanitize_id() {
  local raw="$1"
  local clean
  clean="$(printf '%s' "${raw}" | tr -cd 'A-Za-z0-9._-')"
  printf '%s' "${clean}"
}

task_id="${CLINE_TASK_ID:-}"

if [[ -z "${task_id}" ]] && command -v jq >/dev/null 2>&1 && [[ -n "${stdin_json}" ]]; then
  task_id="$(jq -r '.taskId // .task.taskId // .event.taskId // empty' <<<"${stdin_json}" 2>/dev/null || true)"
fi

run_id=""
if [[ -n "${task_id}" ]]; then
  run_id="$(sanitize_id "${task_id}")"
fi

if [[ -n "${run_id}" ]]; then
  rm -f "/tmp/mighty_scan_result_${run_id}.json" "/tmp/mighty_scan_error_${run_id}.txt" >/dev/null 2>&1 || true
else
  rm -f /tmp/mighty_scan_result_*.json /tmp/mighty_scan_error_*.txt >/dev/null 2>&1 || true
fi

exit 0
