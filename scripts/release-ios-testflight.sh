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
flutter build ios --release
cd ios
bundle update fastlane
bundle exec fastlane beta
cd ..
