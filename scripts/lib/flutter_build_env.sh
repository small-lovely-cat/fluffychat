#!/usr/bin/env bash

FLUFFYCHAT_FLUTTER_BUILD_ARGS=()

# 收集 Flutter 构建时需要注入的 dart-define 参数。
# 当前统一从环境变量读取敏感配置，避免把值硬编码到仓库中。
collect_fluffychat_flutter_build_args() {
  FLUFFYCHAT_FLUTTER_BUILD_ARGS=()

  if [[ -n "${SENTRY_DSN:-}" ]]; then
    FLUFFYCHAT_FLUTTER_BUILD_ARGS+=(
      --dart-define
      "SENTRY_DSN=${SENTRY_DSN}"
    )
  fi
}
