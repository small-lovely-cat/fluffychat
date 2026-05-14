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

# 安全执行 flutter build，兼容 set -u 下空数组展开的情况。
#
# 参数说明：
# - $1：flutter build 的目标子命令，例如 apk、appbundle、ios、ipa、macos、linux、web。
# - $@：后续参数会原样透传给对应的 flutter build 子命令。
#
# 返回值说明：
# - 返回 flutter build 命令的退出状态码。
run_fluffychat_flutter_build() {
  local build_target="$1"
  shift

  if [[ ${#FLUFFYCHAT_FLUTTER_BUILD_ARGS[@]} -gt 0 ]]; then
    flutter build "${build_target}" "${FLUFFYCHAT_FLUTTER_BUILD_ARGS[@]}" "$@"
    return
  fi

  flutter build "${build_target}" "$@"
}
