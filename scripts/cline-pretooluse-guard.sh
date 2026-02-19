#!/usr/bin/env bash

# Cline PreToolUse hook: scan risky tool invocations with Citadel (local HTTP),
# plus a small hard-block regex fallback for obvious footguns/secrets.

set -uo pipefail

stdin_json="$(cat 2>/dev/null || true)"

stderr_log() {
  # Single-line log to stderr for readability in Cline UI.
  local msg="$1"
  msg="$(printf '%s' "${msg}" | tr '\r\n' '  ' | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//')"
  if [[ -n "${msg}" ]]; then
    printf '%s\n' "${msg}" >&2
  fi
}

dotenv_set_if_empty() {
  # Load only known-safe keys from .env files. Never echo values.
  local key="$1"
  local val="$2"

  case "${key}" in
    MIGHTY_API_KEY | MIGHTY_GATEWAY_URL | MIGHTY_PREFER_GATEWAY | MIGHTY_PROFILE | MIGHTY_ANALYSIS_MODE | MIGHTY_MULTIMODAL_FILES | MIGHTY_MAX_FILE_MB | MIGHTY_TIMEOUT_SECONDS | MIGHTY_CONTEXT | MIGHTY_CONTENT_TYPE | MIGHTY_THRESHOLD_MODE | MIGHTY_BLOCK_CONFIDENCE_PCT | MIGHTY_WARN_CONFIDENCE_PCT | CITADEL_PORT | CITADEL_MODE | CITADEL_TIMEOUT_SECONDS | CITADEL_DEBUG)
      ;;
    *)
      return 0
      ;;
  esac

  if [[ -z "${!key-}" && -n "${val}" ]]; then
    export "${key}=${val}"
  fi
}

load_dotenv_file() {
  local file="$1"
  [[ -f "${file}" ]] || return 0

  local line key val
  while IFS= read -r line || [[ -n "${line}" ]]; do
    # Trim CR (Windows) + surrounding whitespace.
    line="${line%%$'\r'}"
    line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

    [[ -z "${line}" ]] && continue
    [[ "${line}" == \#* ]] && continue

    # Allow "export KEY=VAL" and "KEY=VAL".
    line="${line#export }"

    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"

      # Strip trailing comments for unquoted values.
      if [[ "${val}" != \"*\" && "${val}" != \'*\' ]]; then
        val="${val%%#*}"
      fi

      # Trim again.
      val="$(printf '%s' "${val}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

      # Strip surrounding quotes if present.
      if [[ "${val}" =~ ^\".*\"$ ]]; then
        val="${val:1:${#val}-2}"
      elif [[ "${val}" =~ ^\'.*\'$ ]]; then
        val="${val:1:${#val}-2}"
      fi

      dotenv_set_if_empty "${key}" "${val}"
    fi
  done <"${file}"
}

load_dotenv() {
  # Best-effort .env loading so hooks work even when VS Code doesn't inherit shell env.
  local base_dir="$1"

  local candidates=()
  if [[ -n "${base_dir}" ]]; then
    candidates+=("${base_dir%/}/.env" "${base_dir%/}/.env.local")
  fi
  candidates+=("${HOME}/Documents/Cline/.env" "${HOME}/.env")

  local f
  for f in "${candidates[@]}"; do
    load_dotenv_file "${f}"
  done
}

one_line() {
  # Normalize text into a single readable line (no newlines, collapsed whitespace).
  local msg="$1"
  printf '%s' "${msg}" | tr '\r\n' '  ' | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//'
}

truncate_one_line() {
  local msg
  msg="$(one_line "$1")"
  local max="$2"
  if [[ -n "${max}" && "${max}" =~ ^[0-9]+$ && ${#msg} -gt ${max} ]]; then
    if [[ "${max}" -gt 3 ]]; then
      msg="${msg:0:$((max - 3))}..."
    else
      msg="${msg:0:${max}}"
    fi
  fi
  printf '%s' "${msg}"
}

humanize_reason() {
  # Turn structured scan results into a short, human-friendly reason line.
  local raw_reason="$1"
  local top_category="$2"

  local out=""
  if [[ -n "${top_category}" ]]; then
    case "${top_category}" in
      *prompt_injection* | *injection*)
        out="prompt injection detected"
        ;;
      *jailbreak*)
        out="jailbreak attempt detected"
        ;;
      *credential* | *secret* | *api_key* | *token* | *key*)
        out="possible secret/credential exposure"
        ;;
      *)
        # Keep it generic for unknown categories to avoid overwhelming messages.
        out="unsafe content detected"
        ;;
    esac
  fi

  if [[ -z "${out}" ]]; then
    out="${raw_reason}"
  fi

  truncate_one_line "${out}" 160
}

is_number() {
  [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

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
  jq -r '.workspaceRoots[0] // .workspacePath // .cwd // .projectPath // empty' <<<"${stdin_json}" 2>/dev/null || true
)"
if [[ -z "${repo}" ]]; then
  repo="$(pwd 2>/dev/null || echo "")"
fi

load_dotenv "${repo}"

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
debug_scan_decision=""
debug_scan_category=""
debug_scan_confidence_pct=""
debug_scan_risk_score=""
debug_scan_scan_id=""
debug_scan_file=""
debug_scan_evidence=""

emit() {
  local cancel_json="$1"        # true|false
  local error_message="$2"      # string (may be empty)
  local context_modification="$3" # string (may be empty)
  local citadel_used_json="$4"  # true|false
  local citadel_ok_json="$5"    # true|false

  jq -cn \
    --arg errorMessage "${error_message}" \
    --arg contextModification "${context_modification}" \
    --arg tool "${tool}" \
    --arg citadelUrl "${debug_scan_url}" \
    --arg citadelEndpoint "${debug_scan_endpoint}" \
    --arg citadelBackend "${debug_scan_backend}" \
    --arg citadelHttp "${debug_scan_http}" \
    --arg decision "${debug_scan_decision}" \
    --arg category "${debug_scan_category}" \
    --arg confidencePct "${debug_scan_confidence_pct}" \
    --arg riskScore "${debug_scan_risk_score}" \
    --arg scanId "${debug_scan_scan_id}" \
    --arg scannedFile "${debug_scan_file}" \
    --arg evidence "${debug_scan_evidence}" \
    --argjson cancel "${cancel_json}" \
    --argjson includeDebug "${debug_enabled}" \
    --argjson citadelUsed "${citadel_used_json}" \
    --argjson citadelOk "${citadel_ok_json}" \
    '(
      ({cancel:$cancel}
        + (if ($errorMessage|length) > 0 then {errorMessage:$errorMessage} else {} end)
        + (if ($contextModification|length) > 0 then {contextModification:$contextModification} else {} end)
      )
      + (if $includeDebug then
          {debug:(
            {citadelUsed:$citadelUsed,citadelOk:$citadelOk,citadelUrl:$citadelUrl,tool:$tool,backend:$citadelBackend,endpoint:$citadelEndpoint,httpCode:$citadelHttp}
            + {scan:(
              {}
              + (if ($decision|length) > 0 then {decision:$decision} else {} end)
              + (if ($category|length) > 0 then {category:$category} else {} end)
              + (if ($confidencePct|length) > 0 then {confidencePct:$confidencePct} else {} end)
              + (if ($riskScore|length) > 0 then {riskScore:$riskScore} else {} end)
              + (if ($scanId|length) > 0 then {scanId:$scanId} else {} end)
              + (if ($scannedFile|length) > 0 then {file:$scannedFile} else {} end)
              + (if ($evidence|length) > 0 then {evidence:$evidence} else {} end)
            )}
          )}
        else {} end)
    )'
}

fallback_pattern=""
if printf '%s' "${payload}" | LC_ALL=C grep -Eq 'AKIA[0-9A-Z]{16}'; then
  fallback_pattern="AWS access key (AKIA...)"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eq 'ghp_[A-Za-z0-9]{20,}'; then
  fallback_pattern="GitHub token (ghp_...)"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eq 'sk-[A-Za-z0-9]{20,}'; then
  fallback_pattern="API key (sk-...)"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eiq 'curl[[:space:]]+[^|]+[|][[:space:]]*(sh|bash)'; then
  fallback_pattern="curl | sh"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eiq 'rm[[:space:]]+-rf[[:space:]]+/'; then
  fallback_pattern="rm -rf /"
elif printf '%s' "${payload}" | LC_ALL=C grep -Eiq 'chmod[[:space:]]+777'; then
  fallback_pattern="chmod 777"
fi

if [[ -n "${fallback_pattern}" ]]; then
  msg="Blocked: detected ${fallback_pattern}. Use env vars for secrets; don't pipe curl to shell; inspect scripts first."
  stderr_log "Mighty Guardrails: ${msg}"
  emit \
    "true" \
    "${msg}" \
    "" \
    "false" \
    "false"
  exit 0
fi

extract_existing_media_path() {
  local text="$1"
  local base_dir="$2"

  # Pull likely file tokens with common media extensions, including quoted paths.
  local matches
  matches="$(
    printf '%s' "${text}" \
      | LC_ALL=C grep -Eo "\"[^\"]+\\.(png|jpe?g|gif|webp|pdf|tiff?|bmp|heic|heif)\"|'[^']+\\.(png|jpe?g|gif|webp|pdf|tiff?|bmp|heic|heif)'|[^[:space:]]+\\.(png|jpe?g|gif|webp|pdf|tiff?|bmp|heic|heif)" \
      | tr -d '"' \
      | tr -d "'" \
      || true
  )"

  local cand
  while IFS= read -r cand; do
    [[ -z "${cand}" ]] && continue

    # Handle tokens like --file=/path/to/a.png
    cand="${cand##*=}"
    # Strip common trailing punctuation
    cand="${cand%%[);,]}"

    if [[ "${cand}" == ~/* ]]; then
      cand="${HOME}/${cand#~/}"
    fi

    local path="${cand}"
    if [[ "${cand}" != /* ]]; then
      path="${base_dir%/}/${cand}"
    fi

    if [[ -f "${path}" ]]; then
      printf '%s\n' "${path}"
      return 0
    fi
  done <<<"${matches}"

  return 1
}

scanned_file_basename=""

scan_attempted="false"
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
  scan_attempted="true"
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

try_gateway_multimodal_file() {
  # Only possible with hosted Gateway + API key.
  if [[ -z "${mighty_api_key}" ]]; then
    return 1
  fi
  if [[ "${tool}" != "execute_command" ]]; then
    return 1
  fi

  local enabled="${MIGHTY_MULTIMODAL_FILES:-1}"
  if [[ "${enabled}" == "0" ]]; then
    return 1
  fi

  local media_path
  media_path="$(extract_existing_media_path "${payload}" "${repo}" || true)"
  if [[ -z "${media_path}" ]]; then
    return 1
  fi

  local max_mb="${MIGHTY_MAX_FILE_MB:-10}"
  local max_bytes=$((max_mb * 1024 * 1024))
  local size_bytes
  size_bytes="$(wc -c <"${media_path}" 2>/dev/null | tr -d ' ' || echo 0)"
  if [[ "${size_bytes}" -le 0 || "${size_bytes}" -gt "${max_bytes}" ]]; then
    return 1
  fi

  if ! command -v base64 >/dev/null 2>&1; then
    return 1
  fi

  local ext="${media_path##*.}"
  local ext_lower
  ext_lower="$(printf '%s' "${ext}" | tr '[:upper:]' '[:lower:]')"
  local content_type="document"
  case "${ext_lower}" in
    png | jpg | jpeg | gif | webp | bmp | tif | tiff | heic | heif)
      content_type="image"
      ;;
    pdf)
      content_type="pdf"
      ;;
  esac

  local context="vision"
  if [[ "${content_type}" == "pdf" ]]; then
    context="pdf_text"
  elif [[ "${content_type}" == "document" ]]; then
    context="document_text"
  fi

  local tmp_b64
  tmp_b64="$(mktemp 2>/dev/null || mktemp -t mighty)"
  if ! base64 <"${media_path}" | tr -d '\n' >"${tmp_b64}"; then
    rm -f "${tmp_b64}" >/dev/null 2>&1 || true
    return 1
  fi

  local file_name
  file_name="$(basename "${media_path}")"

  local mm_body
  mm_body="$(
    jq -cn \
      --rawfile content "${tmp_b64}" \
      --arg scan_phase "${scan_phase}" \
      --arg content_type "${content_type}" \
      --arg profile "${MIGHTY_PROFILE:-balanced}" \
      --arg analysis_mode "${MIGHTY_ANALYSIS_MODE:-secure}" \
      --arg context "${context}" \
      --arg tool "${tool}" \
      --arg repo "${repo}" \
      --arg filename "${file_name}" \
      '{content:$content,content_type:$content_type,scan_phase:$scan_phase,profile:$profile,analysis_mode:$analysis_mode,context:$context,metadata:{tool:$tool,repo:$repo,filename:$filename}}'
  )"

  rm -f "${tmp_b64}" >/dev/null 2>&1 || true

  scan_backend="mighty-gateway"
  scan_post "${gateway_base_url}" "/v1/scan" "${mm_body}" -H "X-API-Key: ${mighty_api_key}"
  if [[ "${scan_http}" == "200" && -n "${scan_response}" ]]; then
    scanned_file_basename="${file_name}"
    return 0
  fi

  return 1
}

if [[ -n "${mighty_api_key}" && "${prefer_gateway}" == "1" ]]; then
  try_gateway_multimodal_file || try_gateway || try_local || true
else
  try_gateway_multimodal_file || try_local || try_gateway || true
fi

scan_ok="false"
if [[ "${scan_http}" == "200" && -n "${scan_response}" ]]; then
  scan_ok="true"
fi

decision="$(
  jq -r '(.decision // .action // .result.action // .result.decision // .verdict // "")' <<<"${scan_response}" 2>/dev/null || true
)"
reason="$(
  jq -r '(.reason // .message // .explanation // .result.reason // "")' <<<"${scan_response}" 2>/dev/null || true
)"

if [[ -z "${reason}" ]]; then
  reason="$(
    jq -r '
      if ((.threats|type)=="array" and (.threats|length) > 0) then
        (.threats[0] | ([.category, .reason] | map(select(. != null and . != "")) | join(": ")))
      else
        ""
      end
    ' <<<"${scan_response}" 2>/dev/null || true
  )"
fi

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

decision_used="false"
if [[ -n "${decision_upper}" ]]; then
  decision_used="true"
fi

citadel_used="false"
if [[ "${scan_ok}" == "true" && "${decision_used}" == "true" ]]; then
  citadel_used="true"
fi

scanner_name="Citadel"
if [[ "${scan_backend}" == "mighty-gateway" ]]; then
  scanner_name="Mighty Gateway"
elif [[ "${scan_backend}" == "citadel-local" ]]; then
  scanner_name="Citadel (local)"
fi

risk_score="$(
  jq -r '(.risk_score // .result.risk_score // "")' <<<"${scan_response}" 2>/dev/null || true
)"
top_confidence="$(
  jq -r '
    if ((.threats|type)=="array" and (.threats|length) > 0) then
      (.threats[0].confidence // "")
    else
      ""
    end
  ' <<<"${scan_response}" 2>/dev/null || true
)"
top_evidence="$(
  jq -r '
    if ((.threats|type)=="array" and (.threats|length) > 0) then
      (.threats[0].evidence // "")
    else
      ""
    end
  ' <<<"${scan_response}" 2>/dev/null || true
)"

confidence_pct=""
if is_number "${top_confidence}"; then
  confidence_pct="$(awk -v c="${top_confidence}" 'BEGIN{printf "%.0f", c*100}')"
elif is_number "${risk_score}"; then
  # Some scanners return a 0-100 style score instead of 0-1 confidence.
  confidence_pct="$(printf '%.0f' "${risk_score}" 2>/dev/null || true)"
fi

scanned_file_note=""
if [[ -n "${scanned_file_basename}" ]]; then
  scanned_file_note=" (${scanned_file_basename})"
fi

top_category="$(
  jq -r '
    if ((.threats|type)=="array" and (.threats|length) > 0) then
      (.threats[0].category // "")
    else
      ""
    end
  ' <<<"${scan_response}" 2>/dev/null || true
)"
reason_human="$(humanize_reason "${reason}" "${top_category}")"

evidence_excerpt=""
if [[ "${scan_backend}" == "mighty-gateway" && -n "${scanned_file_basename}" && -n "${top_evidence}" ]]; then
  evidence_excerpt="$(truncate_one_line "${top_evidence}" 140)"

  # Never include secret-looking strings in evidence.
  if printf '%s' "${evidence_excerpt}" | LC_ALL=C grep -Eq 'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}'; then
    evidence_excerpt=""
  fi

  case "${top_category}" in
    *credential* | *secret* | *api_key* | *token* | *key*)
      evidence_excerpt=""
      ;;
  esac
fi

decision_effective="${decision_upper}"
threshold_mode="${MIGHTY_THRESHOLD_MODE:-0}"
warn_pct="${MIGHTY_WARN_CONFIDENCE_PCT:-60}"
block_pct="${MIGHTY_BLOCK_CONFIDENCE_PCT:-90}"

# Optional: override ALLOW/WARN/BLOCK using confidence percentage (Gateway only).
# This is useful if you want a "WARN range" where Cline can surface an approve/deny UI.
if [[ "${scan_backend}" == "mighty-gateway" && "${threshold_mode}" == "1" && "${confidence_pct}" =~ ^[0-9]+$ && "${warn_pct}" =~ ^[0-9]+$ && "${block_pct}" =~ ^[0-9]+$ ]]; then
  if ((confidence_pct >= block_pct)); then
    decision_effective="BLOCK"
  elif ((confidence_pct >= warn_pct)); then
    decision_effective="WARN"
  else
    decision_effective="ALLOW"
  fi
fi

debug_scan_decision="${decision_effective}"
debug_scan_category="${top_category}"
debug_scan_confidence_pct="${confidence_pct}"
debug_scan_risk_score="${risk_score}"
debug_scan_file="${scanned_file_basename}"
debug_scan_evidence="${evidence_excerpt}"
debug_scan_scan_id="$(
  jq -r '(.scan_id // .result.scan_id // "")' <<<"${scan_response}" 2>/dev/null || true
)"

case "${decision_effective}" in
  BLOCK)
    if [[ -z "${reason_human}" ]]; then
      reason_human="policy violation"
    fi

    backend_label="${scanner_name}"
    if [[ "${scan_backend}" == "mighty-gateway" && -n "${scanned_file_basename}" ]]; then
      backend_label="Mighty Gateway (multimodal)"
    fi

    msg="Mighty Guardrails blocked ${tool} via ${backend_label}: ${reason_human}${scanned_file_note}"
    if [[ -n "${confidence_pct}" ]]; then
      msg="${msg} (conf ${confidence_pct}%)"
    fi
    if [[ -n "${evidence_excerpt}" ]]; then
      msg="${msg}. Evidence: ${evidence_excerpt}"
    fi
    msg="$(truncate_one_line "${msg}" 260)"
    stderr_log "Mighty Guardrails: ${msg}"
    emit "true" "${msg}" "" "${citadel_used}" "${scan_ok}"
    ;;
  WARN)
    if [[ -z "${reason_human}" ]]; then
      reason_human="policy warning"
    fi

    backend_label="${scanner_name}"
    if [[ "${scan_backend}" == "mighty-gateway" && -n "${scanned_file_basename}" ]]; then
      backend_label="Mighty Gateway (multimodal)"
    fi

    msg="Mighty Guardrails warning via ${backend_label}: ${reason_human}${scanned_file_note}"
    if [[ -n "${confidence_pct}" ]]; then
      msg="${msg} (conf ${confidence_pct}%)"
    fi
    if [[ -n "${evidence_excerpt}" ]]; then
      msg="${msg}. Evidence: ${evidence_excerpt}"
    fi
    msg="$(truncate_one_line "${msg}" 260)"
    stderr_log "Mighty Guardrails: ${msg}"
    emit "false" "" "${msg}" "${citadel_used}" "${scan_ok}"
    ;;
  *)
    emit "false" "" "" "${citadel_used}" "${scan_ok}"
    ;;
esac
