#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-build/macos}"
WORKSPACE="${WORKSPACE:-macos/Runner.xcworkspace}"
SCHEME="${SCHEME:-Runner}"
CONFIGURATION="${CONFIGURATION:-Release}"

flutter pub get
flutter build macos --config-only --release
pod install --project-directory=macos

# GitHub-hosted runners don't carry this project's Apple signing setup,
# so we compile with Xcode while explicitly disabling signing.
xcodebuild \
  -workspace "${WORKSPACE}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  build
