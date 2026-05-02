import 'package:flutter/material.dart';

/// Bundled emoji font family name declared in pubspec.
const kBundledEmojiFontFamily = 'NotoColorEmoji';

/// Platform default UI font to keep non-emoji text unchanged.
String systemUiFontFamily(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => 'CupertinoSystemText',
  TargetPlatform.windows => 'Segoe UI',
  TargetPlatform.android ||
  TargetPlatform.fuchsia ||
  TargetPlatform.linux => 'Roboto',
};

/// Shared emoji fallback chain used across text and emoji pickers.
const kEmojiFontFamilyFallback = <String>[
  kBundledEmojiFontFamily,
  'Apple Color Emoji',
  'Noto Color Emoji',
  'Segoe UI Emoji',
];

const kEmojiTextStyle = TextStyle(fontFamilyFallback: kEmojiFontFamilyFallback);
