#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-build/macos/Build/Products/Release/FluffyChat.app}"
OUTPUT_PATH="${2:-build/macos/FluffyChat-macos.zip}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "macOS app bundle not found: ${APP_PATH}" >&2
  exit 1
fi

rm -f "${OUTPUT_PATH}"
mkdir -p "$(dirname "${OUTPUT_PATH}")"
ditto -c -k --keepParent "${APP_PATH}" "${OUTPUT_PATH}"

echo "Packaged ${OUTPUT_PATH}"
