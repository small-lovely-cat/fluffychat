import 'package:flutter/material.dart';

/// Bundled emoji font family name declared in pubspec.
const kBundledEmojiFontFamily = 'NotoColorEmoji';

/// Shared emoji fallback chain used across text and emoji pickers.
const kEmojiFontFamilyFallback = <String>[
  kBundledEmojiFontFamily,
  'Apple Color Emoji',
  'Noto Color Emoji',
  'Segoe UI Emoji',
];

const kEmojiTextStyle = TextStyle(fontFamilyFallback: kEmojiFontFamilyFallback);
