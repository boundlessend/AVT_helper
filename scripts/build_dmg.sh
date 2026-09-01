#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AVT_helper"
BUILD_DIR="${ROOT_DIR}/.build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
STAGE_DIR="${BUILD_DIR}/dmg_stage"

"${ROOT_DIR}/scripts/build_app.sh"

rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_DIR}" "${STAGE_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGE_DIR}/Applications"

# имя тома несёт версию, чтобы смонтированный образ отличался от ранее скачанного
VOLUME_NAME="${APP_NAME} $(plutil -extract CFBundleShortVersionString raw -o - "${APP_DIR}/Contents/Info.plist")"

rm -f "${DMG_PATH}"
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_PATH}"
rm -rf "${STAGE_DIR}"

# готовый образ проверяем монтированием: битый dmg должен падать здесь, а не у пользователя
MOUNT_DIR="$(mktemp -d)"
unmount_image() {
  hdiutil detach "${MOUNT_DIR}" -quiet >/dev/null 2>&1 || true
  rmdir "${MOUNT_DIR}" >/dev/null 2>&1 || true
}
trap unmount_image EXIT

hdiutil attach -nobrowse -readonly -mountpoint "${MOUNT_DIR}" "${DMG_PATH}" >/dev/null

if [ ! -d "${MOUNT_DIR}/${APP_NAME}.app" ]; then
  echo "The disk image has no ${APP_NAME}.app inside" >&2
  exit 1
fi

if [ ! -L "${MOUNT_DIR}/Applications" ]; then
  echo "The disk image has no symlink to /Applications" >&2
  exit 1
fi

echo "Created ${DMG_PATH}"
