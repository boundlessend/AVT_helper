#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AVT_helper"
BUILD_DIR="${ROOT_DIR}/.build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
EXECUTABLE_PATH="${ROOT_DIR}/.build/release/${APP_NAME}"
ICON_SOURCE="${ROOT_DIR}/Assets/AVT_helper_icon.png"
ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"

RELEASE_VERSION="$(git -C "${ROOT_DIR}" describe --tags --abbrev=0 2>/dev/null | sed -E 's/^v\.?//' || true)"
RELEASE_VERSION="${RELEASE_VERSION:-0.0.0}"

# CFBundleVersion обязан расти между сборками, поэтому это число коммитов, а не версия релиза
BUILD_NUMBER="$(git -C "${ROOT_DIR}" rev-list --count HEAD 2>/dev/null || echo 1)"

# год копирайта берётся у последнего коммита, а не у часов машины: пересборка
# старого тега не должна менять строку в бандле
COPYRIGHT_YEAR="$(git -C "${ROOT_DIR}" log -1 --format=%cd --date=format:%Y 2>/dev/null || echo 2026)"

# сборка вне тега или с незакоммиченными правками помечается как dev, иначе она выдаёт себя за релиз
if git -C "${ROOT_DIR}" describe --tags --exact-match >/dev/null 2>&1 && [ -z "$(git -C "${ROOT_DIR}" status --porcelain)" ]; then
  BUILD_STAGE="release"
else
  COMMIT="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  BUILD_STAGE="dev.${COMMIT}"
fi

cd "${ROOT_DIR}"
swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# ресурсный бандл SwiftPM с переводами: без него в интерфейсе останутся одни ключи
cp -R "${ROOT_DIR}/.build/release/${APP_NAME}_${APP_NAME}.bundle" "${RESOURCES_DIR}/"

# иконка собирается из одного исходника: хранить десять срезов в репозитории незачем
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"
for SIZE in 16 32 128 256 512; do
  sips -z "${SIZE}" "${SIZE}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${SIZE}x${SIZE}.png" >/dev/null
  sips -z "$((SIZE * 2))" "$((SIZE * 2))" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil --convert icns "${ICONSET_DIR}" --output "${RESOURCES_DIR}/AVT_helper.icns"
rm -rf "${ICONSET_DIR}"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>app.boundlessend.avt-helper</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${RELEASE_VERSION}</string>
    <key>AVTBuildStage</key>
    <string>${BUILD_STAGE}</string>
    <key>CFBundleIconFile</key>
    <string>AVT_helper</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>© ${COPYRIGHT_YEAR} @boundlessend. BSD 3-Clause.</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>CFBundleLocalizations</key>
    <array>
      <string>ru</string>
      <string>en</string>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
      <dict>
        <key>UTTypeIdentifier</key>
        <string>org.aegisub.ass</string>
        <key>UTTypeDescription</key>
        <string>Advanced SubStation Alpha subtitles</string>
        <key>UTTypeConformsTo</key>
        <array>
          <string>public.plain-text</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
          <key>public.filename-extension</key>
          <array>
            <string>ass</string>
          </array>
        </dict>
      </dict>
      <dict>
        <key>UTTypeIdentifier</key>
        <string>org.aegisub.ssa</string>
        <key>UTTypeDescription</key>
        <string>SubStation Alpha subtitles</string>
        <key>UTTypeConformsTo</key>
        <array>
          <string>public.plain-text</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
          <key>public.filename-extension</key>
          <array>
            <string>ssa</string>
          </array>
        </dict>
      </dict>
      <dict>
        <key>UTTypeIdentifier</key>
        <string>app.boundlessend.avt-helper.srp</string>
        <key>UTTypeDescription</key>
        <string>SRP dubbing script</string>
        <key>UTTypeConformsTo</key>
        <array>
          <string>public.xml</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
          <key>public.filename-extension</key>
          <array>
            <string>srp</string>
          </array>
        </dict>
      </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
      <dict>
        <key>CFBundleTypeName</key>
        <string>Subtitle file</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
          <string>org.aegisub.ass</string>
          <string>org.aegisub.ssa</string>
          <string>cz.wz.zuggy.subrip</string>
          <string>org.w3.webvtt</string>
          <string>app.boundlessend.avt-helper.srp</string>
        </array>
      </dict>
    </array>
  </dict>
</plist>
PLIST

codesign --force --sign - "${APP_DIR}"

echo "Created ${APP_DIR}"
