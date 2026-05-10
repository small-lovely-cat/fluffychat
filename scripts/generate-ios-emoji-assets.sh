#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

if ! command -v dart >/dev/null 2>&1; then
  echo "dart is required to generate iOS emoji assets." >&2
  exit 1
fi

mkdir -p assets/generated/ios_emoji_webp

dart run scripts/generate_ios_emoji_assets.dart "$@"
