import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:flutter/material.dart';

import 'latest_emoji_set.dart';

final _emojiSetCache = <String, List<CategoryEmoji>>{};

List<CategoryEmoji> getLatestEmojiLocale(Locale locale) {
  return _emojiSetCache.putIfAbsent(locale.languageCode, () {
    final localizedEmojiSet = getDefaultEmojiLocale(locale);
    final localizedNamesByEmoji = <String, String>{
      for (final category in localizedEmojiSet)
        for (final emoji in category.emoji) emoji.emoji: emoji.name,
    };

    return latestEmojiSet
        .map(
          (category) => CategoryEmoji(category.category, [
            for (final emoji in category.emoji)
              emoji.copyWith(
                name: localizedNamesByEmoji[emoji.emoji] ?? emoji.name,
              ),
          ]),
        )
        .toList(growable: false);
  });
}
