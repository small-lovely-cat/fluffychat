import 'package:fluffychat/config/emoji_font.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_linkify/flutter_linkify.dart';

import 'latest_emoji_set.dart';

final Set<String> _latestEmojiLookup = Set.unmodifiable({
  for (final category in latestEmojiSet)
    for (final emoji in category.emoji) emoji.emoji,
});

const _variationSelector16 = 0xFE0F;
const _skinToneModifierMin = 0x1F3FB;
const _skinToneModifierMax = 0x1F3FF;

final Set<String> _latestEmojiNormalizedLookup = Set.unmodifiable({
  for (final emoji in _latestEmojiLookup) _normalizeEmojiLookupKey(emoji),
});

String _normalizeEmojiLookupKey(String value) {
  final filteredRunes = <int>[];
  for (final rune in value.runes) {
    if (rune == _variationSelector16) continue;
    if (rune >= _skinToneModifierMin && rune <= _skinToneModifierMax) {
      continue;
    }
    filteredRunes.add(rune);
  }
  return String.fromCharCodes(filteredRunes);
}

bool isLatestEmojiGrapheme(String grapheme) {
  if (_latestEmojiLookup.contains(grapheme)) return true;
  return _latestEmojiNormalizedLookup.contains(
    _normalizeEmojiLookupKey(grapheme),
  );
}

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

InlineSpan buildEmojiAwareLinkifySpan({
  required String text,
  TextStyle? textStyle,
  TextStyle? linkStyle,
  LinkifyOptions options = const LinkifyOptions(),
  LinkCallback? onOpen,
  bool useMouseRegion = false,
}) {
  final linkifySpan = LinkifySpan(
    text: text,
    style: textStyle,
    options: options,
    linkStyle: linkStyle,
    onOpen: onOpen,
    useMouseRegion: useMouseRegion,
  );

  final spans = <InlineSpan>[];
  for (final child in linkifySpan.children ?? const <InlineSpan>[]) {
    if (child is! TextSpan || child.text == null || child.children != null) {
      spans.add(child);
      continue;
    }
    spans.addAll(
      buildEmojiAwareTextSpans(
        child.text!,
        textStyle: child.style ?? textStyle,
        recognizer: child.recognizer,
        mouseCursor: child.mouseCursor,
        onEnter: child.onEnter,
        onExit: child.onExit,
        semanticsLabel: child.semanticsLabel,
        semanticsIdentifier: child.semanticsIdentifier,
        locale: child.locale,
        spellOut: child.spellOut,
      ),
    );
  }
  return TextSpan(children: spans);
}

class EmojiAwareText extends StatelessWidget {
  const EmojiAwareText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: buildEmojiAwareTextSpans(
          text,
          textStyle: style ?? DefaultTextStyle.of(context).style,
        ),
      ),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
    );
  }
}

class EmojiAwareLinkify extends StatelessWidget {
  const EmojiAwareLinkify({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.onOpen,
    this.options = const LinkifyOptions(),
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap = true,
    this.textScaler,
    this.textScaleFactor,
    this.useMouseRegion = true,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final LinkCallback? onOpen;
  final LinkifyOptions options;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool softWrap;
  final TextScaler? textScaler;
  final double? textScaleFactor;
  final bool useMouseRegion;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final effectiveTextScaler =
        textScaler ??
        (textScaleFactor != null
            ? TextScaler.linear(textScaleFactor!)
            : TextScaler.noScaling);
    return Text.rich(
      buildEmojiAwareLinkifySpan(
        text: text,
        textStyle: baseStyle,
        linkStyle: baseStyle
            .copyWith(
              color: const Color(0xFF448AFF),
              decoration: TextDecoration.underline,
            )
            .merge(linkStyle),
        onOpen: onOpen,
        options: options,
        useMouseRegion: useMouseRegion,
      ),
      textScaler: effectiveTextScaler,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
    );
  }
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
