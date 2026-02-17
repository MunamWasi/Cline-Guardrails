#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "Missing dependency: ${name}" >&2
    return 1
  fi
}

missing=0
need_cmd bash || missing=1
need_cmd jq || missing=1
need_cmd curl || missing=1

if [[ "${missing}" == "1" ]]; then
  echo "" >&2
  echo "Install missing deps (macOS):" >&2
  echo "  brew install jq" >&2
  exit 1
fi

echo "OK: bash, jq, curl" >&2

if [[ -x "${ROOT_DIR}/bin/citadel" ]]; then
  echo "OK: Citadel binary found at ${ROOT_DIR}/bin/citadel" >&2
  exit 0
fi

if command -v citadel >/dev/null 2>&1; then
  echo "OK: Citadel binary found in PATH: $(command -v citadel)" >&2
  exit 0
fi

echo "" >&2
echo "Citadel binary not found. Build Citadel OSS (heuristics-only, no heavy model downloads):" >&2
echo "  1) git clone https://github.com/TryMightyAI/citadel" >&2
echo "  2) cd citadel" >&2
echo "  3) go build -o \"${ROOT_DIR}/bin/citadel\" ./cmd/gateway" >&2
echo "" >&2
echo "Notes:" >&2
echo "  - Citadel OSS serves a local HTTP sidecar: ./bin/citadel serve 8787" >&2
echo "  - Optional (not recommended for fast demos): CITADEL_AUTO_DOWNLOAD_MODEL=true downloads large models." >&2

