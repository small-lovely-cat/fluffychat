import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/emoji_font.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_mixed_emoji_picker.dart';
import 'package:fluffychat/utils/emoji/emoji_kitchen_reaction_service.dart';
import 'package:fluffychat/utils/emoji/emoji_kitchen_service.dart';
import 'package:fluffychat/utils/emoji/latest_emoji_locale.dart';
import 'package:fluffychat/utils/emoji/platform_emoji_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// 自定义 reaction 选择面板，支持普通 emoji 与 mixed emoji。
class CustomReactionPicker extends StatelessWidget {
  final Event event;
  final Set<String> sentReactions;
  final VoidCallback onReactionSelected;

  const CustomReactionPicker({
    required this.event,
    required this.sentReactions,
    required this.onReactionSelected,
    super.key,
  });

  /// 处理普通 emoji reaction 选择事件。
  ///
  /// - Parameters:
  ///   - context: 当前界面上下文。
  ///   - reaction: 用户选中的 emoji reaction。
  /// - Returns: 无返回值。
  Future<void> _handleEmojiReactionSelected(
    BuildContext context,
    String reaction,
  ) async {
    if (sentReactions.contains(reaction)) {
      return;
    }
    onReactionSelected();
    await event.room.sendReaction(event.eventId, reaction);
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  /// 处理 mixed emoji reaction 选择事件。
  ///
  /// - Parameters:
  ///   - context: 当前界面上下文。
  ///   - combination: 用户选中的 mixed emoji 组合图。
  /// - Returns: 无返回值。
  Future<void> _handleMixedReactionSelected(
    BuildContext context,
    EmojiKitchenCombination combination,
  ) async {
    if (!context.mounted) {
      return;
    }
    await EmojiKitchenReactionService.sendMixedReaction(
      context: context,
      event: event,
      combination: combination,
    );
    if (!context.mounted) {
      return;
    }
    onReactionSelected();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).customReaction),
          leading: CloseButton(
            onPressed: () => Navigator.of(context).pop(null),
          ),
          bottom: TabBar(
            tabs: [
              Tab(
                icon: Icon(
                  Icons.emoji_emotions_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              Tab(
                icon: Icon(
                  Icons.interests_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SizedBox(
              height: double.infinity,
              child: PlatformEmojiPicker(
                onEmojiSelected: (_, emoji) => _handleEmojiReactionSelected(
                  context,
                  emoji.emoji,
                ),
                config: Config(
                  locale: Localizations.localeOf(context),
                  checkPlatformCompatibility: false,
                  emojiSet: getLatestEmojiLocale,
                  emojiTextStyle: kEmojiTextStyle,
                  emojiViewConfig: const EmojiViewConfig(
                    backgroundColor: Colors.transparent,
                  ),
                  bottomActionBarConfig: const BottomActionBarConfig(
                    enabled: false,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    initCategory: Category.SMILEYS,
                    backspaceColor: theme.colorScheme.primary,
                    iconColor: theme.colorScheme.primary.withAlpha(128),
                    iconColorSelected: theme.colorScheme.primary,
                    indicatorColor: theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surface,
                  ),
                  skinToneConfig: SkinToneConfig(
                    dialogBackgroundColor: Color.lerp(
                      theme.colorScheme.surface,
                      theme.colorScheme.primaryContainer,
                      0.75,
                    )!,
                    indicatorColor: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            ChatMixedEmojiPicker(
              onSendCombination: (combination) =>
                  _handleMixedReactionSelected(context, combination),
            ),
          ],
        ),
      ),
    );
  }
}
