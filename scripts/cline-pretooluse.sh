#!/usr/bin/env bash

# Stable Cline PreToolUse hook runner for Mighty Guardrails.
# Contract:
# - BLOCK => exactly one JSON object on stdout.
# - WARN  => one single-line stderr warning, no stdout.
# - ALLOW => completely silent (stdout/stderr), exit 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNER_BIN_DEFAULT="${SCRIPT_DIR}/mighty-guardrails"
INNER_BIN="${MIGHTY_GUARDRAILS_INNER_BIN:-${INNER_BIN_DEFAULT}}"

stdin_json="$(cat 2>/dev/null || true)"
[[ -z "${stdin_json}" ]] && exit 0

have_jq="0"
if command -v jq >/dev/null 2>&1; then
  have_jq="1"
fi

json_get() {
  local expr="$1"
  if [[ "${have_jq}" == "1" ]]; then
    jq -r "${expr}" <<<"${stdin_json}" 2>/dev/null || true
  fi
}

sanitize_id() {
  local raw="$1"
  local clean
  clean="$(printf '%s' "${raw}" | tr -cd 'A-Za-z0-9._-')"
  if [[ -z "${clean}" ]]; then
    clean="$(date +%s%N 2>/dev/null || date +%s)"
  fi
  printf '%s' "${clean}"
}

task_id="${CLINE_TASK_ID:-}"
if [[ -z "${task_id}" ]]; then
  task_id="$(json_get '.taskId // empty')"
fi
if [[ -z "${task_id}" ]]; then
  task_id="$(date +%s%N 2>/dev/null || date +%s)"
fi

RUN_ID="$(sanitize_id "${task_id}")"
TMP_RESULT="/tmp/mighty_scan_result_${RUN_ID}.json"
TMP_ERROR="/tmp/mighty_scan_error_${RUN_ID}.txt"

# Always create both temp artifacts.
: >"${TMP_RESULT}"
: >"${TMP_ERROR}"

workspace_root="$(json_get '.workspaceRoots[0] // .workspacePath // .cwd // .projectPath // empty')"
if [[ -z "${workspace_root}" ]]; then
  workspace_root="$(pwd 2>/dev/null || echo "")"
fi
repo_root="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd || true)"

dotenv_set_if_empty() {
  local key="$1"
  local val="$2"

  case "${key}" in
    MIGHTY_API_KEY | MIGHTY_MODE | MIGHTY_WARN_THRESHOLD | MIGHTY_BLOCK_THRESHOLD | MIGHTY_GATEWAY_URL | MIGHTY_PREFER_GATEWAY | MIGHTY_PROFILE | MIGHTY_ANALYSIS_MODE | MIGHTY_MULTIMODAL_FILES | MIGHTY_MAX_FILE_MB | CITADEL_PORT | CITADEL_MODE | CITADEL_TIMEOUT_SECONDS)
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
    line="${line%%$'\r'}"
    line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "${line}" ]] && continue
    [[ "${line}" == \#* ]] && continue
    line="${line#export }"

    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      if [[ "${val}" != \"*\" && "${val}" != \'*\' ]]; then
        val="${val%%#*}"
      fi
      val="$(printf '%s' "${val}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      if [[ "${val}" =~ ^\".*\"$ ]]; then
        val="${val:1:${#val}-2}"
      elif [[ "${val}" =~ ^\'.*\'$ ]]; then
        val="${val:1:${#val}-2}"
      fi
      dotenv_set_if_empty "${key}" "${val}"
    fi
  done <"${file}"
}

load_dotenv_candidates() {
  local f
  if [[ -n "${workspace_root}" ]]; then
    load_dotenv_file "${workspace_root%/}/.env"
    load_dotenv_file "${workspace_root%/}/.env.local"
  fi
  if [[ -n "${repo_root}" ]]; then
    load_dotenv_file "${repo_root%/}/.env"
    load_dotenv_file "${repo_root%/}/.env.local"
  fi
  for f in "${HOME}/Documents/Cline/.env" "${HOME}/.env"; do
    load_dotenv_file "${f}"
  done
}

load_dotenv_candidates

# Mode control for pro vs oss.
mode_lc="$(printf '%s' "${MIGHTY_MODE:-}" | tr '[:upper:]' '[:lower:]')"
case "${mode_lc}" in
  pro)
    export MIGHTY_PREFER_GATEWAY="${MIGHTY_PREFER_GATEWAY:-1}"
    ;;
  oss)
    unset MIGHTY_API_KEY || true
    export MIGHTY_PREFER_GATEWAY="0"
    ;;
esac

is_number() {
  [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

float_ge() {
  local left="$1"
  local right="$2"
  awk -v l="${left}" -v r="${right}" 'BEGIN{if (l+0 >= r+0) exit 0; exit 1}'
}

normalize_one_line() {
  local msg="$1"
  printf '%s' "${msg}" | tr '\r\n' '  ' | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//'
}

truncate_line() {
  local msg="$1"
  local max="${2:-220}"
  msg="$(normalize_one_line "${msg}")"
  if [[ "${#msg}" -gt "${max}" ]]; then
    if [[ "${max}" -gt 3 ]]; then
      msg="${msg:0:$((max - 3))}..."
    else
      msg="${msg:0:${max}}"
    fi
  fi
  printf '%s' "${msg}"
}

redact_text() {
  local text="$1"
  local api_key="${MIGHTY_API_KEY:-}"

  if command -v perl >/dev/null 2>&1; then
    REDACT_API_KEY="${api_key}" perl -pe '
      if (length($ENV{REDACT_API_KEY} // "")) {
        s/\Q$ENV{REDACT_API_KEY}\E/[REDACTED_MIGHTY_API_KEY]/g;
      }
      s/\bsk-[A-Za-z0-9_-]{10,}\b/[REDACTED_SK]/g;
      s/\bghp_[A-Za-z0-9]{20,}\b/[REDACTED_GITHUB_TOKEN]/g;
      s/\bAKIA[0-9A-Z]{16}\b/[REDACTED_AWS_KEY]/g;
      s/\b([A-Za-z_][A-Za-z0-9_]*(?:KEY|TOKEN|SECRET)[A-Za-z0-9_]*)\s*=\s*("[^"]*"|[^\s",}]+)/$1=[REDACTED]/ig;
    ' <<<"${text}"
    return
  fi

  if [[ -n "${api_key}" ]]; then
    text="${text//${api_key}/[REDACTED_MIGHTY_API_KEY]}"
  fi
  text="$(printf '%s' "${text}" | sed -E \
    -e 's/sk-[A-Za-z0-9_-]{10,}/[REDACTED_SK]/g' \
    -e 's/ghp_[A-Za-z0-9]{20,}/[REDACTED_GITHUB_TOKEN]/g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED_AWS_KEY]/g' \
    -e "s/([A-Za-z_][A-Za-z0-9_]*(KEY|TOKEN|SECRET)[A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*'|[^[:space:]\\\",}]+)/\\1=[REDACTED]/gI")"
  printf '%s' "${text}"
}

json_quote() {
  local s="$1"
  if [[ "${have_jq}" == "1" ]]; then
    jq -Rn --arg v "${s}" '$v'
    return
  fi

  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  printf '"%s"' "${s}"
}

# If scanner is missing, fail open silently to avoid breaking Cline.
if [[ ! -x "${INNER_BIN}" ]]; then
  exit 0
fi

if ! printf '%s\n' "${stdin_json}" | "${INNER_BIN}" >"${TMP_RESULT}" 2>"${TMP_ERROR}"; then
  # The inner scanner may exit non-zero; we still normalize its output.
  :
fi

raw_stdout="$(cat "${TMP_RESULT}" 2>/dev/null || true)"
raw_stderr="$(cat "${TMP_ERROR}" 2>/dev/null || true)"

# Redact before any downstream handling and persist only redacted temp artifacts.
safe_stdout="$(redact_text "${raw_stdout}")"
safe_stderr="$(redact_text "${raw_stderr}")"
printf '%s' "${safe_stdout}" >"${TMP_RESULT}"
printf '%s' "${safe_stderr}" >"${TMP_ERROR}"

decision="allow"        # allow|warn|block
confidence=""           # 0..1 float
reason=""               # user-visible message body

if [[ -n "${safe_stdout}" && "${have_jq}" == "1" ]] && jq -e . >/dev/null 2>&1 <<<"${safe_stdout}"; then
  cancel="$(jq -r 'if (.cancel // false) then "true" else "false" end' <<<"${safe_stdout}" 2>/dev/null || echo "false")"
  decision_raw="$(jq -r '(.decision // .action // .result.action // .result.decision // .verdict // "") | tostring' <<<"${safe_stdout}" 2>/dev/null || true)"
  reason="$(jq -r '(.errorMessage // .reason // .message // .explanation // .body // .result.reason // .result.message // .result.body // .contextModification // .warningMessage // .threats[0].reason // .threats[0].evidence // "") | tostring' <<<"${safe_stdout}" 2>/dev/null || true)"
  confidence_raw="$(jq -r '(.confidence // .result.confidence // .threats[0].confidence // .risk_score // .result.risk_score // "") | tostring' <<<"${safe_stdout}" 2>/dev/null || true)"

  decision_upper="$(printf '%s' "${decision_raw}" | tr '[:lower:]' '[:upper:]')"
  if [[ "${cancel}" == "true" || "${decision_upper}" == "BLOCK" || "${decision_upper}" == "DENY" || "${decision_upper}" == "REJECT" ]]; then
    decision="block"
  elif [[ "${decision_upper}" == "WARN" || "${decision_upper}" == "WARNING" ]]; then
    decision="warn"
  fi

  if is_number "${confidence_raw}"; then
    if float_ge "${confidence_raw}" "1.000001"; then
      confidence="$(awk -v c="${confidence_raw}" 'BEGIN{printf "%.2f", c/100.0}')"
    else
      confidence="$(awk -v c="${confidence_raw}" 'BEGIN{printf "%.2f", c}')"
    fi
  fi
else
  reason="${safe_stdout}"
  if [[ -z "${reason}" ]]; then
    reason="${safe_stderr}"
  fi

  if printf '%s' "${reason}" | grep -Eiq 'blocked|block(ed)? by|dangerous command|detected curl[[:space:]]*[|][[:space:]]*sh'; then
    decision="block"
  elif printf '%s' "${reason}" | grep -Eiq 'warn|warning'; then
    decision="warn"
  fi
fi

reason="$(truncate_line "${reason}" 220)"
if [[ -z "${reason}" ]]; then
  reason="policy violation detected"
fi

warn_threshold="${MIGHTY_WARN_THRESHOLD:-0.70}"
block_threshold="${MIGHTY_BLOCK_THRESHOLD:-0.85}"
if [[ -n "${confidence}" ]] && is_number "${warn_threshold}" && is_number "${block_threshold}"; then
  if float_ge "${confidence}" "${block_threshold}"; then
    decision="block"
  elif float_ge "${confidence}" "${warn_threshold}" && [[ "${decision}" != "block" ]]; then
    decision="warn"
  fi
fi

if [[ -z "${confidence}" ]]; then
  confidence="0.00"
fi

if [[ "${decision}" == "block" ]]; then
  if printf '%s' "${reason}" | grep -Eiq 'detected curl[[:space:]]*[|][[:space:]]*sh|curl[[:space:]]*[|][[:space:]]*sh'; then
    block_msg="Blocked by Host Guardrails (Cline): ${reason}"
  else
    block_msg="Blocked by Mighty Guardrails (confidence: ${confidence}): ${reason}"
  fi
  block_msg="$(truncate_line "${block_msg}" 260)"
  printf '{"cancel":true,"errorMessage":%s}\n' "$(json_quote "${block_msg}")"
  exit 0
fi

if [[ "${decision}" == "warn" ]]; then
  warn_msg="Mighty Guardrails warning (confidence: ${confidence}): ${reason} (allowed to proceed)"
  warn_msg="$(truncate_line "${warn_msg}" 260)"
  printf '%s\n' "${warn_msg}" >&2
fi

exit 0
