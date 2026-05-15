import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class StartChatFab extends StatelessWidget {
  const StartChatFab({super.key});

  @override
  Widget build(BuildContext context) {
    return TFab(
      theme: TFabTheme.primary,
      icon: const Icon(TIcons.chat_bubble_add, color: Colors.white),
      text: L10n.of(context).newChat,
      onClick: () => context.go('/rooms/newprivatechat'),
    );
  }
}
