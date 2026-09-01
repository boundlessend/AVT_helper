#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AVT_helper"
"${ROOT_DIR}/scripts/build_app.sh"

# open только выводит вперёд уже запущенную копию, поэтому прежний экземпляр закрываем до запуска
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  osascript -e 'quit application id "app.boundlessend.avt-helper"' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "${APP_NAME}" >/dev/null 2>&1 || break
    sleep 0.3
  done
  pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
fi

open "${ROOT_DIR}/.build/${APP_NAME}.app"
