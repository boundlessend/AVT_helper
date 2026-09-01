#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

# swift format входит в тулчейн Swift 6, а brew install без версии давал плавающий набор правил,
# поэтому отсутствие форматтера - это ошибка окружения, а не повод ставить другой
if ! swift format --version >/dev/null 2>&1; then
  echo "swift format is not available in the toolchain" >&2
  exit 1
fi

swift format lint --strict --recursive Sources Tests
