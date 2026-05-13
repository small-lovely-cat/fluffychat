#!/bin/sh -ve
flutter clean
flutter pub get
dart run scripts/prepare_emoji_kitchen_metadata.dart
cd ios
rm -rf Pods
rm -f Podfile.lock
pod install
pod update
cd ..
if [ -n "${SENTRY_DSN:-}" ]; then
  flutter build ios --release --dart-define "SENTRY_DSN=${SENTRY_DSN}"
else
  flutter build ios --release
fi
cd ios
bundle update fastlane
bundle exec fastlane beta
cd ..
