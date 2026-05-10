import 'package:fluffychat/utils/platform_infos.dart';

import 'generated_emoji_assets.dart';

const _variationSelector16 = 0xFE0F;
const _skinToneModifierMin = 0x1F3FB;
const _skinToneModifierMax = 0x1F3FF;

bool get shouldUseGeneratedEmojiAssets =>
    PlatformInfos.isIOS && kGeneratedIosEmojiAssetLookupKeys.isNotEmpty;

String canonicalizeGeneratedEmojiAssetKey(String value) {
  final filteredRunes = <int>[];
  for (final rune in value.runes) {
    if (rune == _variationSelector16) continue;
    filteredRunes.add(rune);
  }
  return String.fromCharCodes(filteredRunes);
}

String stripEmojiSkinToneModifiers(String value) {
  final filteredRunes = <int>[];
  for (final rune in value.runes) {
    if (rune >= _skinToneModifierMin && rune <= _skinToneModifierMax) {
      continue;
    }
    filteredRunes.add(rune);
  }
  return String.fromCharCodes(filteredRunes);
}

String? resolveGeneratedEmojiAssetPath(String emoji) {
  if (!shouldUseGeneratedEmojiAssets) return null;

  final exactKey = canonicalizeGeneratedEmojiAssetKey(emoji);
  if (kGeneratedIosEmojiAssetLookupKeys.contains(exactKey)) {
    return _assetPathForCanonicalKey(exactKey);
  }

  final baseKey = stripEmojiSkinToneModifiers(exactKey);
  if (kGeneratedIosEmojiAssetLookupKeys.contains(baseKey)) {
    return _assetPathForCanonicalKey(baseKey);
  }

  return null;
}

String _assetPathForCanonicalKey(String canonicalKey) =>
    '$kGeneratedIosEmojiAssetBasePath/${_emojiFileStem(canonicalKey)}.webp';

String _emojiFileStem(String value) => value.runes
    .map((rune) => rune.toRadixString(16).toUpperCase().padLeft(4, '0'))
    .join('-');
