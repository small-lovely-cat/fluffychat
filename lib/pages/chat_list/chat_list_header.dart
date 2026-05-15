import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../../widgets/matrix.dart';
import '../../widgets/tdesign/tdesign_scope.dart';

class ChatListHeader extends StatelessWidget implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;

  const ChatListHeader({
    super.key,
    required this.controller,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;

    return SliverToBoxAdapter(
      child: StreamBuilder(
        stream: client.onSyncStatus.stream,
        builder: (context, snapshot) {
          final status =
              client.onSyncStatus.value ??
              const SyncStatusUpdate(SyncStatus.waitingForResponse);
          final hide =
              client.onSync.value != null &&
              status.status != SyncStatus.error &&
              client.prevBatch != null;
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: TDesignSectionCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          L10n.of(context).chats,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!controller.isSearchMode)
                        ClientChooserButton(controller),
                      if (controller.isSearchMode && globalSearch)
                        TButton(
                          text: controller.isSearching
                              ? '...'
                              : controller.searchServer ??
                                    Matrix.of(context).client.homeserver!.host,
                          type: TButtonType.text,
                          icon: TIcons.edit_1,
                          onTap: controller.isSearching
                              ? null
                              : controller.setServer,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TSearchBar(
                    controller: controller.searchController,
                    focusNode: controller.searchFocusNode,
                    mediumStyle: true,
                    autoHeight: true,
                    backgroundColor: Colors.transparent,
                    placeHolder: hide
                        ? L10n.of(context).searchChatsRooms
                        : status.calcLocalizedString(context),
                    action: controller.isSearchMode
                        ? L10n.of(context).cancel
                        : '',
                    needCancel: controller.isSearchMode,
                    onActionClick: (_) => controller.cancelSearch(),
                    onInputClick: controller.startSearch,
                    onTextChanged: (text) => controller.onSearchEnter(
                      text,
                      globalSearch: globalSearch,
                    ),
                    onSubmitted: (text) => controller.onSearchEnter(
                      text,
                      globalSearch: globalSearch,
                    ),
                  ),
                  if (!hide) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                            value: status.progress,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            status.calcLocalizedString(context),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
