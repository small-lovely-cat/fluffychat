#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/scripts/lib/flutter_build_env.sh"

if [[ -n "${WEB_BUILD_CONFIG_JSON:-}" ]]; then
  printf '%s' "${WEB_BUILD_CONFIG_JSON}" > config.json
  if command -v jq >/dev/null 2>&1; then
    jq empty config.json >/dev/null
  fi
fi

bash ./scripts/prepare-web.sh
dart run scripts/prepare_emoji_kitchen_metadata.dart

build_args=(
  --release
  --source-maps
  --dart-define
  "FLUTTER_WEB_CANVASKIT_URL=${WEB_BUILD_CANVASKIT_URL:-canvaskit/}"
)

if [[ -n "${WEB_BUILD_BASE_HREF:-}" ]]; then
  build_args+=(--base-href "${WEB_BUILD_BASE_HREF}")
fi

if [[ -n "${WEB_BUILD_PWA_STRATEGY:-}" ]]; then
  build_args+=(--pwa-strategy "${WEB_BUILD_PWA_STRATEGY}")
fi

if [[ -n "${WEB_BUILD_DART_DEFINES:-}" ]]; then
  while IFS= read -r define || [[ -n "${define}" ]]; do
    [[ -n "${define}" ]] || continue
    build_args+=(--dart-define "${define}")
  done <<< "${WEB_BUILD_DART_DEFINES}"
fi

collect_fluffychat_flutter_build_args
build_args+=("${FLUFFYCHAT_FLUTTER_BUILD_ARGS[@]}")

if [[ -n "${WEB_BUILD_EXTRA_ARGS:-}" ]]; then
  read -r -a extra_args <<< "${WEB_BUILD_EXTRA_ARGS}"
  build_args+=("${extra_args[@]}")
fi

flutter build web "${build_args[@]}"

if [[ -f config.json ]]; then
  cp config.json build/web/config.json
fi
