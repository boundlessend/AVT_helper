#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AVT_helper"
BUILD_DIR="${ROOT_DIR}/.build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/AVT_helper.dmg"

"${ROOT_DIR}/scripts/build_app.sh"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install it with: brew install create-dmg" >&2
  exit 1
fi

rm -f "${DMG_PATH}" "${BUILD_DIR}/${APP_NAME}-"*.dmg

create-dmg \
  --overwrite \
  --no-version-in-filename \
  --no-code-sign \
  --dmg-title "${APP_NAME}" \
  "${APP_DIR}" \
  "${BUILD_DIR}"

echo "Created ${DMG_PATH}"
