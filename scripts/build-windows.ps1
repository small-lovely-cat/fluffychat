flutter doctor
flutter config --enable-windows-desktop
flutter clean
flutter pub get
dart run scripts/prepare_emoji_kitchen_metadata.dart

$buildArgs = @("windows", "--release", "-v")
if ($env:SENTRY_DSN) {
  $buildArgs += @("--dart-define", "SENTRY_DSN=$($env:SENTRY_DSN)")
}

flutter build @buildArgs
