#!/usr/bin/env bash

# Test Mighty Gateway multimodal scanning (image/PDF/document) using $MIGHTY_API_KEY.
#
# Usage:
#   MIGHTY_API_KEY=... ./scripts/test-mighty-multimodal.sh /path/to/file.png
#   MIGHTY_API_KEY=... ./scripts/test-mighty-multimodal.sh /path/to/file.pdf output

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_dotenv_value() {
  # Best-effort, non-executing .env parser for a single key.
  local key="$1"
  local file="$2"
  [[ -f "${file}" ]] || return 1

  local line val
  line="$(LC_ALL=C grep -E "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 || true)"
  [[ -z "${line}" ]] && return 1

  line="${line#export }"
  val="${line#*=}"
  val="${val%%$'\r'}"

  # Strip inline comments for unquoted values.
  if [[ "${val}" != \"*\" && "${val}" != \'*\' ]]; then
    val="${val%%#*}"
  fi

  val="$(printf '%s' "${val}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ "${val}" =~ ^\".*\"$ ]]; then
    val="${val:1:${#val}-2}"
  elif [[ "${val}" =~ ^\'.*\'$ ]]; then
    val="${val:1:${#val}-2}"
  fi

  printf '%s' "${val}"
}

if [[ -z "${MIGHTY_API_KEY:-}" ]]; then
  for f in "${ROOT_DIR}/.env" "${ROOT_DIR}/.env.local" "${HOME}/Documents/Cline/.env" "${HOME}/.env"; do
    key="$(load_dotenv_value "MIGHTY_API_KEY" "${f}" || true)"
    if [[ -n "${key}" ]]; then
      export MIGHTY_API_KEY="${key}"
      break
    fi
  done
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing dependency: jq" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "Missing dependency: curl" >&2
  exit 1
fi
if ! command -v base64 >/dev/null 2>&1; then
  echo "Missing dependency: base64" >&2
  exit 1
fi

file_path="${1:-}"
scan_phase="${2:-input}"

if [[ -z "${file_path}" ]]; then
  echo "Usage: $0 <file_path> [input|output]" >&2
  exit 1
fi

if [[ ! -f "${file_path}" ]]; then
  echo "File not found: ${file_path}" >&2
  exit 1
fi

if [[ -z "${MIGHTY_API_KEY:-}" ]]; then
  echo "Set MIGHTY_API_KEY in your environment (do not paste it into files)." >&2
  exit 1
fi

base_url="${MIGHTY_GATEWAY_URL:-https://gateway.trymighty.ai}"
timeout_seconds="${MIGHTY_TIMEOUT_SECONDS:-30}"
profile="${MIGHTY_PROFILE:-balanced}"
analysis_mode="${MIGHTY_ANALYSIS_MODE:-secure}"
context="${MIGHTY_CONTEXT:-vision}"

content_type="${MIGHTY_CONTENT_TYPE:-auto}"
if [[ "${content_type}" == "auto" ]]; then
  ext="${file_path##*.}"
  ext_lower="$(printf '%s' "${ext}" | tr '[:upper:]' '[:lower:]')"
  case "${ext_lower}" in
    png | jpg | jpeg | gif | webp | bmp | tiff | tif | heic | heif)
      content_type="image"
      ;;
    pdf)
      content_type="pdf"
      ;;
    *)
      content_type="document"
      ;;
  esac
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t mighty)"
b64_file="${tmp_dir}/content.b64"
body_file="${tmp_dir}/body.json"
resp_file="${tmp_dir}/resp.json"

cleanup() {
  rm -rf "${tmp_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Base64 encode without newlines (Gateway expects a single base64 string).
base64 <"${file_path}" | tr -d '\n' >"${b64_file}"

filename="$(basename "${file_path}")"

jq -n \
  --rawfile content "${b64_file}" \
  --arg scan_phase "${scan_phase}" \
  --arg content_type "${content_type}" \
  --arg profile "${profile}" \
  --arg analysis_mode "${analysis_mode}" \
  --arg context "${context}" \
  --arg filename "${filename}" \
  '{
    content: $content,
    scan_phase: $scan_phase,
    content_type: $content_type,
    profile: $profile,
    analysis_mode: $analysis_mode,
    context: $context,
    metadata: { filename: $filename }
  }' >"${body_file}"

url="${base_url}/v1/scan"
http_code="$(
  curl -sS -m "${timeout_seconds}" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: ${MIGHTY_API_KEY}" \
    --data-binary "@${body_file}" \
    -o "${resp_file}" \
    -w '%{http_code}' \
    "${url}"
)"

if [[ "${http_code}" != "200" ]]; then
  echo "Gateway scan failed: HTTP ${http_code} (${url})" >&2
  if jq -e . >/dev/null 2>&1 <"${resp_file}"; then
    jq . <"${resp_file}" >&2
  else
    cat "${resp_file}" >&2
  fi
  exit 1
fi

# Print a compact summary (avoid dumping large extracted_text fields).
jq '{
  action,
  risk_level,
  risk_score,
  content_type_detected,
  processing_ms,
  scan_id,
  scan_status,
  threats: (.threats // [])
}' <"${resp_file}"
