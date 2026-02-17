#!/usr/bin/env bash

# Cline PreToolUse hook: scan risky tool invocations with Citadel (local HTTP),
# plus a small hard-block regex fallback for obvious footguns/secrets.

set -uo pipefail

stdin_json="$(cat 2>/dev/null || true)"

fail_open() {
  printf '%s\n' '{"cancel":false}'
}

if [[ -z "${stdin_json}" ]]; then
  fail_open
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  # Defensive: never brick the agent if jq isn't present.
  fail_open
  exit 0
fi

tool="$(
  jq -r '.preToolUse.toolName // .preToolUse.tool // empty' <<<"${stdin_json}" 2>/dev/null || true
)"

case "${tool}" in
  write_to_file | replace_in_file | execute_command) ;;
  *)
    fail_open
    exit 0
    ;;
esac

repo="$(
  jq -r '.workspaceRoots[0] // .workspacePath // empty' <<<"${stdin_json}" 2>/dev/null || true
)"
if [[ -z "${repo}" ]]; then
  repo="$(pwd 2>/dev/null || echo "")"
fi

payload=""
case "${tool}" in
  write_to_file)
    payload="$(
      jq -r '.preToolUse.parameters.content // .preToolUse.parameters.text // empty' <<<"${stdin_json}" 2>/dev/null || true
    )"
    ;;
  replace_in_file)
    payload="$(
      jq -r '.preToolUse.parameters.diff // empty' <<<"${stdin_json}" 2>/dev/null || true
    )"
    if [[ -z "${payload}" ]]; then
      search="$(
        jq -r '.preToolUse.parameters.search // empty' <<<"${stdin_json}" 2>/dev/null || true
      )"
      replace="$(
        jq -r '.preToolUse.parameters.replace // empty' <<<"${stdin_json}" 2>/dev/null || true
      )"
      if [[ -n "${search}" || -n "${replace}" ]]; then
        payload="${search}"$'\n'"${replace}"
      fi
    fi
    ;;
  execute_command)
    payload="$(
      jq -r '.preToolUse.parameters.command // empty' <<<"${stdin_json}" 2>/dev/null || true
    )"
    ;;
esac

if [[ -z "${payload}" ]]; then
  fail_open
  exit 0
fi

local_citadel_base_url="http://127.0.0.1:${CITADEL_PORT:-8787}"
citadel_mode="${CITADEL_MODE:-input}"
citadel_timeout_seconds="${CITADEL_TIMEOUT_SECONDS:-2}"

gateway_base_url="${MIGHTY_GATEWAY_URL:-https://gateway.trymighty.ai}"
mighty_api_key="${MIGHTY_API_KEY:-}"
prefer_gateway="${MIGHTY_PREFER_GATEWAY:-0}"

debug_enabled="false"
if [[ "${CITADEL_DEBUG:-0}" == "1" ]]; then
  debug_enabled="true"
fi

debug_scan_url="${local_citadel_base_url}"
debug_scan_endpoint=""
debug_scan_backend=""
debug_scan_http="000"

emit() {
  local cancel_json="$1"        # true|false
  local error_message="$2"      # string (may be empty)
  local warning_message="$3"    # string (may be empty)
  local citadel_used_json="$4"  # true|false

  jq -cn \
    --arg errorMessage "${error_message}" \
    --arg warningMessage "${warning_message}" \
    --arg tool "${tool}" \
    --arg citadelUrl "${debug_scan_url}" \
    --arg citadelEndpoint "${debug_scan_endpoint}" \
    --arg citadelBackend "${debug_scan_backend}" \
    --arg citadelHttp "${debug_scan_http}" \
    --argjson cancel "${cancel_json}" \
    --argjson includeDebug "${debug_enabled}" \
    --argjson citadelUsed "${citadel_used_json}" \
    '(
      {cancel:$cancel}
      + (if ($errorMessage|length) > 0 then {errorMessage:$errorMessage} else {} end)
      + (if ($warningMessage|length) > 0 then {warningMessage:$warningMessage} else {} end)
      + (if $includeDebug then {debug:{citadelUsed:$citadelUsed,citadelUrl:$citadelUrl,tool:$tool,backend:$citadelBackend,endpoint:$citadelEndpoint,httpCode:$citadelHttp}} else {} end)
    )'
}

fallback_pattern=""
if printf '%s' "${payload}" | LC_ALL=C grep -Eq 'AKIA[0-9A-Z]{16}'; then
  fallback_pattern="AWS access key (AKIA...)"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eq 'ghp_[A-Za-z0-9]{20,}'; then
  fallback_pattern="GitHub token (ghp_...)"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eq 'sk-[A-Za-z0-9]{20,}'; then
  fallback_pattern="API key (sk-...)"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eiq 'curl[^|]*\\|[[:space:]]*(sh|bash)'; then
  fallback_pattern="curl | sh"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eiq 'rm[[:space:]]+-rf[[:space:]]+/'; then
  fallback_pattern="rm -rf /"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eiq 'chmod[[:space:]]+777'; then
  fallback_pattern="chmod 777"
fi

if [[ -n "${fallback_pattern}" ]]; then
  emit \
    "true" \
    "Blocked: detected ${fallback_pattern}. Use env vars for secrets; don't pipe curl to shell; inspect scripts first." \
    "" \
    "false"
  exit 0
fi

scan_used="false"
scan_response=""
scan_http="000"
scan_backend=""

scan_post() {
  local base_url="$1"
  local endpoint="$2"
  local body="$3"
  shift 3

  local url="${base_url}${endpoint}"
  local tmp

  tmp="$(mktemp 2>/dev/null || mktemp -t citadel)"

  # Curl exit codes should never crash the hook.
  scan_http="$(
    curl -sS -m "${citadel_timeout_seconds}" \
      -H 'Content-Type: application/json' \
      "$@" \
      -o "${tmp}" \
      -w '%{http_code}' \
      -d "${body}" \
      "${url}" 2>/dev/null || true
  )"

  scan_response="$(cat "${tmp}" 2>/dev/null || true)"
  rm -f "${tmp}" 2>/dev/null || true

  debug_scan_url="${base_url}"
  debug_scan_endpoint="${endpoint}"
  debug_scan_backend="${scan_backend}"
  debug_scan_http="${scan_http}"
  scan_used="true"
}

local_scan_body="$(
  jq -cn \
    --arg text "${payload}" \
    --arg mode "${citadel_mode}" \
    --arg tool "${tool}" \
    --arg repo "${repo}" \
    '{text:$text,mode:$mode,metadata:{tool:$tool,repo:$repo}}'
)"

scan_phase="input"
if [[ "${citadel_mode}" == "output" ]]; then
  scan_phase="output"
fi

v1_body="$(
  jq -cn \
    --arg content "${payload}" \
    --arg scan_phase "${scan_phase}" \
    --arg tool "${tool}" \
    --arg repo "${repo}" \
    --arg profile "${MIGHTY_PROFILE:-balanced}" \
    --arg analysis_mode "${MIGHTY_ANALYSIS_MODE:-secure}" \
    '{content:$content,scan_phase:$scan_phase,profile:$profile,analysis_mode:$analysis_mode,metadata:{tool:$tool,repo:$repo}}'
)"

try_local() {
  scan_backend="citadel-local"
  scan_post "${local_citadel_base_url}" "/scan" "${local_scan_body}"
  if [[ "${scan_http}" == "200" && -n "${scan_response}" ]]; then
    return 0
  fi
  # Per requirement: if /scan isn't correct, try /v1/scan as a fallback.
  scan_post "${local_citadel_base_url}" "/v1/scan" "${v1_body}"
  if [[ "${scan_http}" == "200" && -n "${scan_response}" ]]; then
    return 0
  fi
  return 1
}

try_gateway() {
  if [[ -z "${mighty_api_key}" ]]; then
    return 1
  fi
  scan_backend="mighty-gateway"
  scan_post "${gateway_base_url}" "/v1/scan" "${v1_body}" -H "X-API-Key: ${mighty_api_key}"
  if [[ "${scan_http}" == "200" && -n "${scan_response}" ]]; then
    return 0
  fi
  return 1
}

if [[ -n "${mighty_api_key}" && "${prefer_gateway}" == "1" ]]; then
  try_gateway || try_local || true
else
  try_local || try_gateway || true
fi

decision="$(
  jq -r '(.decision // .action // .result.action // .result.decision // .verdict // "")' <<<"${scan_response}" 2>/dev/null || true
)"
reason="$(
  jq -r '(.reason // .message // .explanation // .result.reason // "")' <<<"${scan_response}" 2>/dev/null || true
)"

if [[ -z "${decision}" ]]; then
  # Citadel output scans may return {is_safe: true|false, ...}.
  is_safe="$(
    jq -r '
      if has("is_safe") then (.is_safe|tostring)
      elif ((.result|type) == "object" and (.result|has("is_safe"))) then (.result.is_safe|tostring)
      else ""
      end
    ' <<<"${scan_response}" 2>/dev/null || true
  )"
  if [[ "${is_safe}" == "false" ]]; then
    decision="BLOCK"
    if [[ -z "${reason}" ]]; then
      reason="is_safe=false"
    fi
  elif [[ "${is_safe}" == "true" ]]; then
    decision="ALLOW"
  fi
fi

decision_upper="$(printf '%s' "${decision}" | tr '[:lower:]' '[:upper:]')"

scanner_name="Citadel"
if [[ "${scan_backend}" == "mighty-gateway" ]]; then
  scanner_name="Mighty Gateway"
elif [[ "${scan_backend}" == "citadel-local" ]]; then
  scanner_name="Citadel (local)"
fi

case "${decision_upper}" in
  BLOCK)
    if [[ -z "${reason}" ]]; then
      reason="No reason provided"
    fi
    emit "true" "Blocked by ${scanner_name} for ${tool}: ${reason}" "" "${scan_used}"
    ;;
  WARN)
    if [[ -z "${reason}" ]]; then
      reason="No reason provided"
    fi
    emit "false" "" "Warning from ${scanner_name} for ${tool}: ${reason}" "${scan_used}"
    ;;
  *)
    emit "false" "" "" "${scan_used}"
    ;;
esac
