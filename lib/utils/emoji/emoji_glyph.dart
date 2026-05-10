import 'package:fluffychat/config/emoji_font.dart';
import 'package:flutter/material.dart';

import 'emoji_asset_registry.dart';

class EmojiGlyph extends StatelessWidget {
  const EmojiGlyph(
    this.emoji, {
    super.key,
    this.style,
    this.dimension,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.textAlign,
  });

  final String emoji;
  final TextStyle? style;
  final double? dimension;
  final BoxFit fit;
  final Alignment alignment;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = inheritedStyle.merge(style);
    final effectiveDimension = dimension ?? effectiveStyle.fontSize ?? 14;
    final assetPath = resolveGeneratedEmojiAssetPath(emoji);

    if (assetPath == null) {
      return Text(
        emoji,
        style: kEmojiTextStyle.merge(
          effectiveStyle.copyWith(fontSize: effectiveDimension),
        ),
        textAlign: textAlign,
      );
    }

    return Semantics(
      label: emoji,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: effectiveDimension,
          child: Align(
            alignment: alignment,
            child: Image.asset(
              assetPath,
              width: effectiveDimension,
              height: effectiveDimension,
              fit: fit,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}
