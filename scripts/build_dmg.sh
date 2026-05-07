#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AVT_helper"
BUILD_DIR="${ROOT_DIR}/.build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_ROOT="${BUILD_DIR}/dmg-root"
DMG_PATH="${BUILD_DIR}/AVT_helper.dmg"

"${ROOT_DIR}/scripts/build_app.sh"

rm -rf "${DMG_ROOT}" "${DMG_PATH}"
mkdir -p "${DMG_ROOT}"
cp -R "${APP_DIR}" "${DMG_ROOT}/${APP_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "Created ${DMG_PATH}"
