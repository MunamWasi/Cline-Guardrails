#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT_DIR}/scripts/cline-pretooluse.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for tests" >&2
  exit 1
fi

if [[ ! -x "${RUNNER}" ]]; then
  echo "Runner not executable: ${RUNNER}" >&2
  exit 1
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t mighty-tests)"
cleanup() {
  rm -rf "${tmp_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

payload='{"taskId":"test-task-123","preToolUse":{"tool":"execute_command","parameters":{"command":"echo ok"}}}'

fail() {
  local msg="$1"
  echo "FAIL: ${msg}" >&2
  exit 1
}

make_mock() {
  local name="$1"
  local body="$2"
  local path="${tmp_dir}/${name}"

  cat >"${path}" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
${body}
SCRIPT
  chmod +x "${path}"
  printf '%s' "${path}"
}

run_case() {
  local mock_bin="$1"
  local out_file="$2"
  local err_file="$3"
  shift 3

  local -a env_args=(
    "MIGHTY_GUARDRAILS_INNER_BIN=${mock_bin}"
    "MIGHTY_WARN_THRESHOLD=0.70"
    "MIGHTY_BLOCK_THRESHOLD=0.85"
  )
  while [[ "$#" -gt 0 ]]; do
    env_args+=("$1")
    shift
  done

  printf '%s\n' "${payload}" \
    | env "${env_args[@]}" "${RUNNER}" >"${out_file}" 2>"${err_file}"
}

# 1) Redaction: key + sk + assignment must never leak.
mock_redact="$(make_mock mock-redact.sh "printf '%s\\n' '{\"cancel\":true,\"errorMessage\":\"reason mc_live_demo_key sk-ABCDEF1234567890 API_TOKEN=secret123\"}'")"
out_redact="${tmp_dir}/out-redact.txt"
err_redact="${tmp_dir}/err-redact.txt"
run_case "${mock_redact}" "${out_redact}" "${err_redact}" "MIGHTY_API_KEY=mc_live_demo_key"

[[ -s "${out_redact}" ]] || fail "redaction case did not produce block JSON"
[[ ! -s "${err_redact}" ]] || fail "redaction case should keep stderr empty"

block_cancel="$(jq -r '.cancel // empty' <"${out_redact}" 2>/dev/null || true)"
[[ "${block_cancel}" == "true" ]] || fail "redaction case did not return cancel=true"

redact_msg="$(jq -r '.errorMessage // ""' <"${out_redact}")"
printf '%s' "${redact_msg}" | grep -q "REDACTED_MIGHTY_API_KEY" || fail "MIGHTY_API_KEY was not redacted"
printf '%s' "${redact_msg}" | grep -q "REDACTED_SK" || fail "sk-* token was not redacted"
printf '%s' "${redact_msg}" | grep -q "API_TOKEN=\[REDACTED\]" || fail "*_TOKEN assignment was not redacted"
printf '%s' "${redact_msg}" | grep -q "mc_live_demo_key" && fail "raw MIGHTY_API_KEY leaked"

# 2) Warn threshold: no stdout, single warning line on stderr.
mock_warn="$(make_mock mock-warn.sh "jq -cn '{cancel:false,decision:\"ALLOW\",confidence:0.74,message:\"suspicious but not severe\"}'")"
out_warn="${tmp_dir}/out-warn.txt"
err_warn="${tmp_dir}/err-warn.txt"
run_case "${mock_warn}" "${out_warn}" "${err_warn}"

[[ ! -s "${out_warn}" ]] || fail "warn case must not write stdout"
[[ -s "${err_warn}" ]] || fail "warn case must write one stderr line"
warn_lines="$(wc -l <"${err_warn}" | tr -d ' ')"
[[ "${warn_lines}" == "1" ]] || fail "warn case should emit exactly one line"
printf '%s' "$(cat "${err_warn}")" | grep -q "Mighty Guardrails warning (confidence: 0.74): suspicious but not severe (allowed to proceed)" || fail "warn message format mismatch"

# 3) Block threshold: confidence can force block.
mock_block="$(make_mock mock-block.sh "jq -cn '{cancel:false,decision:\"ALLOW\",confidence:0.91,message:\"high confidence violation\"}'")"
out_block="${tmp_dir}/out-block.txt"
err_block="${tmp_dir}/err-block.txt"
run_case "${mock_block}" "${out_block}" "${err_block}"

[[ -s "${out_block}" ]] || fail "block-threshold case must produce stdout JSON"
[[ ! -s "${err_block}" ]] || fail "block-threshold case should keep stderr empty"
block_msg="$(jq -r '.errorMessage // ""' <"${out_block}")"
printf '%s' "${block_msg}" | grep -q "Blocked by Mighty Guardrails (confidence: 0.91): high confidence violation" || fail "block-threshold message format mismatch"

# 4) Allow formatting: no stdout and no stderr.
mock_allow="$(make_mock mock-allow.sh "printf '%s\\n' '{\"cancel\":false}'")"
out_allow="${tmp_dir}/out-allow.txt"
err_allow="${tmp_dir}/err-allow.txt"
run_case "${mock_allow}" "${out_allow}" "${err_allow}"

[[ ! -s "${out_allow}" ]] || fail "allow case must not write stdout"
[[ ! -s "${err_allow}" ]] || fail "allow case must not write stderr"

# 5) Host label routing: curl|sh phrase should map to Host Guardrails label.
mock_host="$(make_mock mock-host.sh "printf '%s\\n' '{\"cancel\":true,\"errorMessage\":\"Blocked: detected curl | sh. Use env vars for secrets; do not pipe curl to shell; inspect scripts first.\"}'")"
out_host="${tmp_dir}/out-host.txt"
err_host="${tmp_dir}/err-host.txt"
run_case "${mock_host}" "${out_host}" "${err_host}"

host_msg="$(jq -r '.errorMessage // ""' <"${out_host}")"
printf '%s' "${host_msg}" | grep -q "Blocked by Host Guardrails (Cline):" || fail "host guardrails label missing"

echo "PASS: cline-pretooluse runner tests"
