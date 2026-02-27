#!/usr/bin/env bash

# Build a portable release archive for easy sharing/install.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
STAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_NAME="mighty-guardrails-cline_${STAMP}.tar.gz"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"

mkdir -p "${DIST_DIR}"

cd "${ROOT_DIR}"
tar -czf "${ARCHIVE_PATH}" \
  --exclude='.git' \
  --exclude='dist' \
  --exclude='.DS_Store' \
  --exclude='.env' \
  --exclude='.env.*.swp' \
  README.md \
  install.sh \
  .env.template \
  .env.example \
  docs \
  scripts \
  configs \
  bin \
  sephora.png

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "${ARCHIVE_PATH}" > "${ARCHIVE_PATH}.sha256"
fi

echo "Release package created:"
echo "  ${ARCHIVE_PATH}"
if [[ -f "${ARCHIVE_PATH}.sha256" ]]; then
  echo "  ${ARCHIVE_PATH}.sha256"
fi

