#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ "${FLUFFYCHAT_SKIP_PUB_GET:-false}" != "true" ]]; then
  flutter pub get
fi
dart run scripts/prepare_emoji_kitchen_metadata.dart

flutter build "$@"
