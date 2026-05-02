import 'package:fluffychat/config/emoji_font.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'latest_emoji_set.dart';

final Set<String> _latestEmojiLookup = Set.unmodifiable({
  for (final category in latestEmojiSet)
    for (final emoji in category.emoji) emoji.emoji,
});

bool isLatestEmojiGrapheme(String grapheme) =>
    _latestEmojiLookup.contains(grapheme);

List<InlineSpan> buildEmojiAwareTextSpans(
  String text, {
  TextStyle? textStyle,
  TextStyle emojiStyle = kEmojiTextStyle,
  GestureRecognizer? recognizer,
  MouseCursor? mouseCursor,
  void Function(PointerEnterEvent event)? onEnter,
  void Function(PointerExitEvent event)? onExit,
  String? semanticsLabel,
  String? semanticsIdentifier,
  Locale? locale,
  bool? spellOut,
}) {
  if (text.isEmpty) {
    return [
      TextSpan(
        text: text,
        style: textStyle,
        recognizer: recognizer,
        mouseCursor: mouseCursor,
        onEnter: onEnter,
        onExit: onExit,
        semanticsLabel: semanticsLabel,
        semanticsIdentifier: semanticsIdentifier,
        locale: locale,
        spellOut: spellOut,
      ),
    ];
  }

  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  bool? bufferIsEmoji;

  void flushBuffer() {
    final currentIsEmoji = bufferIsEmoji;
    if (buffer.isEmpty || currentIsEmoji == null) return;
    final style = currentIsEmoji
        ? (textStyle ?? const TextStyle()).merge(emojiStyle)
        : textStyle;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: style,
        recognizer: recognizer,
        mouseCursor: mouseCursor,
        onEnter: onEnter,
        onExit: onExit,
        semanticsLabel: semanticsLabel,
        semanticsIdentifier: semanticsIdentifier,
        locale: locale,
        spellOut: spellOut,
      ),
    );
    buffer.clear();
  }

  for (final grapheme in Characters(text)) {
    final isEmoji = isLatestEmojiGrapheme(grapheme);
    if (bufferIsEmoji == null) {
      bufferIsEmoji = isEmoji;
      buffer.write(grapheme);
      continue;
    }
    if (bufferIsEmoji == isEmoji) {
      buffer.write(grapheme);
      continue;
    }
    flushBuffer();
    bufferIsEmoji = isEmoji;
    buffer.write(grapheme);
  }
  flushBuffer();
  return spans;
}

class EmojiAwareTextEditingController extends TextEditingController {
  EmojiAwareTextEditingController({
    super.text,
    this.emojiStyle = kEmojiTextStyle,
  });

  final TextStyle emojiStyle;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    assert(
      !value.composing.isValid || !withComposing || value.isComposingRangeValid,
    );

    final composingRegionOutOfRange =
        !value.isComposingRangeValid || !withComposing;

    if (composingRegionOutOfRange) {
      return TextSpan(
        style: style,
        children: buildEmojiAwareTextSpans(
          text,
          textStyle: style,
          emojiStyle: emojiStyle,
        ),
      );
    }

    final composingStyle =
        style?.merge(const TextStyle(decoration: TextDecoration.underline)) ??
        const TextStyle(decoration: TextDecoration.underline);

    return TextSpan(
      style: style,
      children: [
        ...buildEmojiAwareTextSpans(
          value.composing.textBefore(value.text),
          textStyle: style,
          emojiStyle: emojiStyle,
        ),
        ...buildEmojiAwareTextSpans(
          value.composing.textInside(value.text),
          textStyle: composingStyle,
          emojiStyle: emojiStyle,
        ),
        ...buildEmojiAwareTextSpans(
          value.composing.textAfter(value.text),
          textStyle: style,
          emojiStyle: emojiStyle,
        ),
      ],
    );
  }
}
