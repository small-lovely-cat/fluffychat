import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/emoji/emoji_kitchen_service.dart';
import 'package:flutter/material.dart';

import 'chat.dart';

enum _EmojiKitchenSelectionSide { left, right }

class ChatMixedEmojiPicker extends StatefulWidget {
  final ChatController controller;

  const ChatMixedEmojiPicker({required this.controller, super.key});

  @override
  State<ChatMixedEmojiPicker> createState() => _ChatMixedEmojiPickerState();
}

class _ChatMixedEmojiPickerState extends State<ChatMixedEmojiPicker> {
  late final Future<EmojiKitchenMetadata> _metadataFuture;

  _EmojiKitchenSelectionSide _activeSelectionSide =
      _EmojiKitchenSelectionSide.left;
  String _searchQuery = '';
  String? _selectedLeftEmojiCodepoint;
  String? _selectedRightEmojiCodepoint;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _metadataFuture = EmojiKitchenService.loadMetadata();
  }

  /// 更新当前激活的选择侧。
  ///
  /// - Parameters:
  ///   - selectionSide: 用户当前正在编辑的 emoji 侧。
  /// - Returns: 无返回值。
  void _setActiveSelectionSide(_EmojiKitchenSelectionSide selectionSide) {
    setState(() {
      _activeSelectionSide = selectionSide;
      _searchQuery = '';
    });
  }

  /// 处理 emoji 选择事件。
  ///
  /// - Parameters:
  ///   - metadata: 已加载的 Emoji Kitchen 元数据。
  ///   - entry: 用户点击的 emoji 条目。
  /// - Returns: 无返回值。
  void _handleEmojiSelected(
    EmojiKitchenMetadata metadata,
    EmojiKitchenCatalogEntry entry,
  ) {
    setState(() {
      switch (_activeSelectionSide) {
        case _EmojiKitchenSelectionSide.left:
          _selectedLeftEmojiCodepoint = entry.emojiCodepoint;
          if (_selectedRightEmojiCodepoint != null &&
              metadata.getLatestCombination(
                    entry.emojiCodepoint,
                    _selectedRightEmojiCodepoint!,
                  ) ==
                  null) {
            _selectedRightEmojiCodepoint = null;
          }
          _activeSelectionSide = _EmojiKitchenSelectionSide.right;
          return;
        case _EmojiKitchenSelectionSide.right:
          _selectedRightEmojiCodepoint = entry.emojiCodepoint;
          return;
      }
    });
  }

  /// 根据当前输入和选择状态构建列表数据。
  ///
  /// - Parameters:
  ///   - metadata: 已加载的 Emoji Kitchen 元数据。
  /// - Returns: 当前界面应展示的 emoji 列表。
  List<EmojiKitchenCatalogEntry> _buildVisibleEntries(
    EmojiKitchenMetadata metadata,
  ) {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final Iterable<String> sourceCodepoints;

    switch (_activeSelectionSide) {
      case _EmojiKitchenSelectionSide.left:
        sourceCodepoints = metadata.knownSupportedEmoji;
        break;
      case _EmojiKitchenSelectionSide.right:
        final selectedLeftEmojiCodepoint = _selectedLeftEmojiCodepoint;
        if (selectedLeftEmojiCodepoint == null) {
          return const [];
        }
        sourceCodepoints =
            metadata.getCompatibleEmojiCodepoints(selectedLeftEmojiCodepoint);
        break;
    }

    final entries = sourceCodepoints.map((emojiCodepoint) {
      final emojiData = metadata.data[emojiCodepoint];
      return EmojiKitchenService.getCatalogEntry(
        emojiCodepoint,
        fallbackName: emojiData?.alt,
      );
    }).toList();

    entries.sort((left, right) {
      final leftOrder = metadata.data[left.emojiCodepoint]?.gBoardOrder ?? 0;
      final rightOrder = metadata.data[right.emojiCodepoint]?.gBoardOrder ?? 0;
      return leftOrder.compareTo(rightOrder);
    });

    if (normalizedQuery.isEmpty) {
      return entries;
    }

    return entries.where((entry) {
      final emojiData = metadata.data[entry.emojiCodepoint];
      final terms = <String>[
        entry.name.toLowerCase(),
        if (emojiData != null) emojiData.alt.toLowerCase(),
        if (emojiData != null) ...emojiData.keywords.map((e) => e.toLowerCase()),
      ];
      return terms.any((term) => term.contains(normalizedQuery));
    }).toList();
  }

  /// 发送当前已选中的 Emoji Kitchen 组合图。
  ///
  /// - Parameters:
  ///   - combination: 当前选中的组合图对象。
  /// - Returns: 无返回值。
  Future<void> _sendCombination(EmojiKitchenCombination combination) async {
    if (_isSending) {
      return;
    }
    setState(() => _isSending = true);
    try {
      await widget.controller.sendEmojiKitchenCombination(combination);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmojiKitchenMetadata>(
      future: _metadataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _EmojiKitchenInfoView(
            icon: Icons.error_outline,
            message:
                snapshot.error?.toString() ??
                L10n.of(context).oopsSomethingWentWrong,
          );
        }

        final metadata = snapshot.data!;
        final visibleEntries = _buildVisibleEntries(metadata);
        final selectedLeftEmojiCodepoint = _selectedLeftEmojiCodepoint;
        final selectedRightEmojiCodepoint = _selectedRightEmojiCodepoint;
        final selectedCombination =
            selectedLeftEmojiCodepoint != null &&
                selectedRightEmojiCodepoint != null
            ? metadata.getLatestCombination(
                selectedLeftEmojiCodepoint,
                selectedRightEmojiCodepoint,
              )
            : null;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _EmojiKitchenSelectorButton(
                          title: 'Emoji A',
                          value: selectedLeftEmojiCodepoint == null
                              ? null
                              : EmojiKitchenService.getCatalogEntry(
                                  selectedLeftEmojiCodepoint,
                                  fallbackName:
                                      metadata
                                          .data[selectedLeftEmojiCodepoint]
                                          ?.alt,
                                ),
                          isActive:
                              _activeSelectionSide ==
                              _EmojiKitchenSelectionSide.left,
                          onTap: () => _setActiveSelectionSide(
                            _EmojiKitchenSelectionSide.left,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _EmojiKitchenSelectorButton(
                          title: 'Emoji B',
                          value: selectedRightEmojiCodepoint == null
                              ? null
                              : EmojiKitchenService.getCatalogEntry(
                                  selectedRightEmojiCodepoint,
                                  fallbackName:
                                      metadata
                                          .data[selectedRightEmojiCodepoint]
                                          ?.alt,
                                ),
                          isActive:
                              _activeSelectionSide ==
                              _EmojiKitchenSelectionSide.right,
                          onTap: () => _setActiveSelectionSide(
                            _EmojiKitchenSelectionSide.right,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText:
                          _activeSelectionSide ==
                              _EmojiKitchenSelectionSide.left
                          ? 'Search base emoji'
                          : 'Search mix target',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _EmojiKitchenPreviewCard(
                    combination: selectedCombination,
                    onSend: selectedCombination == null || _isSending
                        ? null
                        : () => _sendCombination(selectedCombination),
                    isSending: _isSending,
                  ),
                ],
              ),
            ),
            Expanded(
              child: visibleEntries.isEmpty
                  ? _EmojiKitchenInfoView(
                      icon: Icons.emoji_emotions_outlined,
                      message:
                          _activeSelectionSide ==
                                  _EmojiKitchenSelectionSide.right &&
                              selectedLeftEmojiCodepoint == null
                          ? 'Select the first emoji to view valid mixes.'
                          : 'No matching emoji found.',
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final crossAxisCount = width >= 560
                            ? 6
                            : width >= 420
                            ? 5
                            : 4;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 1.1,
                              ),
                          itemCount: visibleEntries.length,
                          itemBuilder: (context, index) {
                            final entry = visibleEntries[index];
                            final isSelected =
                                (_activeSelectionSide ==
                                            _EmojiKitchenSelectionSide.left &&
                                        _selectedLeftEmojiCodepoint ==
                                            entry.emojiCodepoint) ||
                                    (_activeSelectionSide ==
                                            _EmojiKitchenSelectionSide.right &&
                                        _selectedRightEmojiCodepoint ==
                                            entry.emojiCodepoint);
                            return _EmojiKitchenEmojiTile(
                              entry: entry,
                              isSelected: isSelected,
                              onTap: () =>
                                  _handleEmojiSelected(metadata, entry),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EmojiKitchenSelectorButton extends StatelessWidget {
  final String title;
  final EmojiKitchenCatalogEntry? value;
  final bool isActive;
  final VoidCallback onTap;

  const _EmojiKitchenSelectorButton({
    required this.title,
    required this.value,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          color: isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            Text(value?.emoji ?? '◻️', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: theme.textTheme.labelMedium),
                  Text(
                    value?.name ?? 'Tap to choose',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiKitchenPreviewCard extends StatelessWidget {
  final EmojiKitchenCombination? combination;
  final VoidCallback? onSend;
  final bool isSending;

  const _EmojiKitchenPreviewCard({
    required this.combination,
    required this.onSend,
    required this.isSending,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: combination == null
          ? Row(
              children: [
                const Icon(Icons.auto_awesome_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pick two supported emoji to generate a mixed image.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    combination!.gStaticUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        combination!.alt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${combination!.leftEmoji} + ${combination!.rightEmoji}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onSend,
                  icon: isSending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(L10n.of(context).send),
                ),
              ],
            ),
    );
  }
}

class _EmojiKitchenEmojiTile extends StatelessWidget {
  final EmojiKitchenCatalogEntry entry;
  final bool isSelected;
  final VoidCallback onTap;

  const _EmojiKitchenEmojiTile({
    required this.entry,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: entry.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
            color: isSelected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surface,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(entry.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 6),
              Text(
                entry.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiKitchenInfoView extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmojiKitchenInfoView({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
