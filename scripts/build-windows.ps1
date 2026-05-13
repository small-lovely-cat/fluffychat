flutter doctor
flutter config --enable-windows-desktop
flutter clean
flutter pub get
dart run scripts/prepare_emoji_kitchen_metadata.dart

flutter build windows --release -v
