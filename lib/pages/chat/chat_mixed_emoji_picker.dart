import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/emoji_font.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/emoji/emoji_glyph.dart';
import 'package:fluffychat/utils/emoji/emoji_kitchen_service.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

import 'chat.dart';

enum _EmojiKitchenSelectionSide { left, right }

const String _emojiKitchenHelpDismissedKey =
    'emoji_kitchen_help_dismissed_v1';

class ChatMixedEmojiPicker extends StatefulWidget {
  final ChatController controller;

  const ChatMixedEmojiPicker({required this.controller, super.key});

  @override
  State<ChatMixedEmojiPicker> createState() => _ChatMixedEmojiPickerState();
}

class _ChatMixedEmojiPickerState extends State<ChatMixedEmojiPicker> {
  late final Future<EmojiKitchenMetadata> _metadataFuture;
  final GlobalKey _headerKey = GlobalKey();

  _EmojiKitchenSelectionSide _activeSelectionSide =
      _EmojiKitchenSelectionSide.left;
  String _searchQuery = '';
  String? _selectedLeftEmojiCodepoint;
  String? _selectedRightEmojiCodepoint;
  bool _isSending = false;
  bool _showHelpTip = false;
  bool _hasLoadedHelpTipState = false;
  double _headerHeight = 0;

  @override
  void initState() {
    super.initState();
    _metadataFuture = EmojiKitchenService.loadMetadata();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasLoadedHelpTipState) {
      return;
    }
    _hasLoadedHelpTipState = true;
    final dismissed = Matrix.of(context).store.getBool(
          _emojiKitchenHelpDismissedKey,
        ) ??
        false;
    _showHelpTip = !dismissed;
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

  /// 关闭首次进入帮助提示。
  ///
  /// - Returns: 无返回值。
  Future<void> _dismissHelpTip() async {
    if (!_showHelpTip) {
      return;
    }
    await Matrix.of(
      context,
    ).store.setBool(_emojiKitchenHelpDismissedKey, true);
    if (!mounted) {
      return;
    }
    setState(() => _showHelpTip = false);
  }

  /// 同步记录头部区域高度，用于定位顶部遮罩层。
  ///
  /// - Returns: 无返回值。
  void _syncHeaderHeight() {
    final context = _headerKey.currentContext;
    if (context == null) {
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    final nextHeight = renderBox?.size.height ?? 0;
    if ((nextHeight - _headerHeight).abs() < 1) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _headerHeight = nextHeight);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<EmojiKitchenMetadata>(
      future: _metadataFuture,
      builder: (context, snapshot) {
        _syncHeaderHeight();
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
        final showPreviewCard = selectedCombination != null || _showHelpTip;

        return SizedBox.expand(
          child: ClipRect(
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    children: [
                      DecoratedBox(
                        key: _headerKey,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          boxShadow: [
                            BoxShadow(
                              color: theme.shadowColor.withAlpha(20),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _EmojiKitchenSelectorButton(
                                      title: 'Emoji A',
                                      value: selectedLeftEmojiCodepoint == null
                                          ? null
                                          : EmojiKitchenService
                                                .getCatalogEntry(
                                                  selectedLeftEmojiCodepoint,
                                                  fallbackName: metadata
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
                                      value:
                                          selectedRightEmojiCodepoint == null
                                          ? null
                                          : EmojiKitchenService
                                                .getCatalogEntry(
                                                  selectedRightEmojiCodepoint,
                                                  fallbackName: metadata
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
                                onChanged: (value) =>
                                    setState(() => _searchQuery = value),
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
                              if (showPreviewCard) ...[
                                const SizedBox(height: 8),
                                _EmojiKitchenPreviewCard(
                                  combination: selectedCombination,
                                  onSend:
                                      selectedCombination == null || _isSending
                                      ? null
                                      : () => _sendCombination(
                                          selectedCombination,
                                        ),
                                  onDismissHelp:
                                      _showHelpTip ? _dismissHelpTip : null,
                                  isSending: _isSending,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRect(
                          child: ColoredBox(
                            color: theme.colorScheme.surface,
                            child: visibleEntries.isEmpty
                                ? _EmojiKitchenInfoView(
                                    icon: Icons.emoji_emotions_outlined,
                                    message:
                                        _activeSelectionSide ==
                                                _EmojiKitchenSelectionSide
                                                    .right &&
                                            selectedLeftEmojiCodepoint == null
                                        ? 'Select the first emoji to view valid mixes.'
                                        : 'No matching emoji found.',
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      final width = constraints.maxWidth;
                                      final crossAxisCount = width >= 560
                                          ? 8
                                          : width >= 420
                                          ? 7
                                          : 6;
                                      return GridView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          8,
                                          12,
                                          12,
                                        ),
                                        clipBehavior: Clip.hardEdge,
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: crossAxisCount,
                                              mainAxisSpacing: 8,
                                              crossAxisSpacing: 8,
                                              mainAxisExtent: 52,
                                            ),
                                        itemCount: visibleEntries.length,
                                        itemBuilder: (context, index) {
                                          final entry = visibleEntries[index];
                                          return _EmojiKitchenEmojiTile(
                                            key: ValueKey(entry.emojiCodepoint),
                                            entry: entry,
                                            onTap: () => _handleEmojiSelected(
                                              metadata,
                                              entry,
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_headerHeight > 0)
                    Positioned(
                      top: _headerHeight,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                theme.colorScheme.surface,
                                theme.colorScheme.surface.withAlpha(0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: 8),
            EmojiGlyph(
              value?.emoji ?? '◻️',
              dimension: 26,
              style: kEmojiTextStyle.merge(const TextStyle(fontSize: 26)),
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
  final VoidCallback? onDismissHelp;
  final bool isSending;

  const _EmojiKitchenPreviewCard({
    required this.combination,
    required this.onSend,
    required this.onDismissHelp,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.auto_awesome_outlined),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pick two supported emoji to generate a mixed image.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (onDismissHelp != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: onDismissHelp,
                    tooltip: L10n.of(context).close,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                  ),
                ],
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
  final VoidCallback onTap;

  const _EmojiKitchenEmojiTile({
    required super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Tooltip(
        message: entry.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          child: Center(
            child: EmojiGlyph(
              entry.emoji,
              dimension: 28,
              style: kEmojiTextStyle.merge(const TextStyle(fontSize: 28)),
            ),
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
