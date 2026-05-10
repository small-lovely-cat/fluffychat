import 'dart:collection';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'emoji_asset_registry.dart';
import 'emoji_glyph.dart';

class PlatformEmojiPicker extends StatelessWidget {
  const PlatformEmojiPicker({
    super.key,
    this.textEditingController,
    this.scrollController,
    this.controller,
    this.onEmojiSelected,
    this.onBackspacePressed,
    this.onCategoryChanged,
    this.config = const Config(),
  });

  final TextEditingController? textEditingController;
  final ScrollController? scrollController;
  final EmojiPickerController? controller;
  final OnEmojiSelected? onEmojiSelected;
  final OnBackspacePressed? onBackspacePressed;
  final OnCategoryChanged? onCategoryChanged;
  final Config config;

  @override
  Widget build(BuildContext context) {
    return EmojiPicker(
      textEditingController: textEditingController,
      scrollController: scrollController,
      controller: controller,
      onEmojiSelected: onEmojiSelected,
      onBackspacePressed: onBackspacePressed,
      onCategoryChanged: onCategoryChanged,
      config: config,
      customWidget: shouldUseGeneratedEmojiAssets
          ? (config, state, showSearchBar) =>
                _GeneratedEmojiPickerView(config, state, showSearchBar)
          : null,
    );
  }
}

class _GeneratedEmojiPickerView extends EmojiPickerView {
  const _GeneratedEmojiPickerView(
    super.config,
    super.state,
    super.showSearchBar, {
    super.key,
  });

  @override
  State<_GeneratedEmojiPickerView> createState() =>
      _GeneratedEmojiPickerViewState();
}

class _GeneratedEmojiPickerViewState extends State<_GeneratedEmojiPickerView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;
  final _scrollController = ScrollController();
  final _emojiPickerUtils = EmojiPickerUtils();
  final _links = HashMap<String, LayerLink>();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    final targetCategory =
        widget.state.currentCategory ??
        widget.config.categoryViewConfig.initCategory;
    var initialIndex = widget.state.categoryEmoji.indexWhere(
      (element) => element.category == targetCategory,
    );
    if (initialIndex == -1) {
      initialIndex = 0;
    }

    _tabController = TabController(
      initialIndex: initialIndex,
      length: widget.state.categoryEmoji.length,
      vsync: this,
    );
    _pageController = PageController(initialPage: initialIndex)
      ..addListener(_closeSkinToneOverlay);
    _scrollController.addListener(_closeSkinToneOverlay);
    widget.state.categoryNavigationNotifier.addListener(
      _onCategoryNavigationChanged,
    );
  }

  @override
  void dispose() {
    widget.state.categoryNavigationNotifier.removeListener(
      _onCategoryNavigationChanged,
    );
    _closeSkinToneOverlay();
    _pageController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final emojiSize = widget.config.emojiViewConfig.getEmojiSize(
          constraints.maxWidth,
        );
        final emojiBoxSize = widget.config.emojiViewConfig.getEmojiBoxSize(
          constraints.maxWidth,
        );
        return EmojiContainer(
          color: widget.config.emojiViewConfig.backgroundColor,
          buttonMode: widget.config.emojiViewConfig.buttonMode,
          child: Column(
            children:
                [
                  widget.config.viewOrderConfig.top,
                  widget.config.viewOrderConfig.middle,
                  widget.config.viewOrderConfig.bottom,
                ].map((item) {
                  switch (item) {
                    case EmojiPickerItem.categoryBar:
                      return widget
                                  .config
                                  .categoryViewConfig
                                  .customCategoryView !=
                              null
                          ? widget
                                .config
                                .categoryViewConfig
                                .customCategoryView!(
                              widget.config,
                              widget.state,
                              _tabController,
                              _pageController,
                            )
                          : DefaultCategoryView(
                              widget.config,
                              widget.state,
                              _tabController,
                              _pageController,
                            );
                    case EmojiPickerItem.emojiView:
                      return Flexible(
                        child: PageView.builder(
                          itemCount: widget.state.categoryEmoji.length,
                          controller: _pageController,
                          onPageChanged: (index) {
                            _tabController.animateTo(
                              index,
                              duration: widget
                                  .config
                                  .categoryViewConfig
                                  .tabIndicatorAnimDuration,
                            );
                            if (index < widget.state.categoryEmoji.length) {
                              widget.state.onCategoryChanged?.call(
                                widget.state.categoryEmoji[index].category,
                              );
                            }
                          },
                          itemBuilder: (context, index) => _buildCategoryPage(
                            emojiSize,
                            emojiBoxSize,
                            widget.state.categoryEmoji[index],
                          ),
                        ),
                      );
                    case EmojiPickerItem.searchBar:
                      if (!widget.config.bottomActionBarConfig.enabled) {
                        return const SizedBox.shrink();
                      }
                      return widget
                                  .config
                                  .bottomActionBarConfig
                                  .customBottomActionBar !=
                              null
                          ? widget
                                .config
                                .bottomActionBarConfig
                                .customBottomActionBar!(
                              widget.config,
                              widget.state,
                              widget.showSearchBar,
                            )
                          : DefaultBottomActionBar(
                              widget.config,
                              widget.state,
                              widget.showSearchBar,
                            );
                  }
                }).toList(),
          ),
        );
      },
    );
  }

  void _onCategoryNavigationChanged() {
    final targetCategory = widget.state.categoryNavigationNotifier.value;
    if (targetCategory == null) return;

    final index = widget.state.categoryEmoji.indexWhere(
      (element) => element.category == targetCategory,
    );
    if (index == -1) return;

    final currentPage = _pageController.page?.round();
    if (index != currentPage) {
      _pageController.jumpToPage(index);
    }
  }

  Widget _buildCategoryPage(
    double emojiSize,
    double emojiBoxSize,
    CategoryEmoji categoryEmoji,
  ) {
    if (categoryEmoji.category == Category.RECENT &&
        categoryEmoji.emoji.isEmpty) {
      return Center(child: widget.config.emojiViewConfig.noRecents);
    }

    return GridView.builder(
      key: const Key('emojiScrollView'),
      scrollDirection: Axis.vertical,
      controller: _scrollController,
      primary: false,
      padding: widget.config.emojiViewConfig.gridPadding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        childAspectRatio: 1,
        crossAxisCount: widget.config.emojiViewConfig.columns,
        mainAxisSpacing: widget.config.emojiViewConfig.verticalSpacing,
        crossAxisSpacing: widget.config.emojiViewConfig.horizontalSpacing,
      ),
      itemCount: categoryEmoji.emoji.length,
      itemBuilder: (context, index) {
        final emoji = categoryEmoji.emoji[index];
        final linkKey = categoryEmoji.category.name + emoji.emoji;
        return _addSkinToneTargetIfAvailable(
          hasSkinTone: emoji.hasSkinTone,
          linkKey: linkKey,
          child: _GeneratedEmojiCell(
            emoji: emoji,
            emojiSize: emojiSize,
            emojiBoxSize: emojiBoxSize,
            buttonMode: widget.config.emojiViewConfig.buttonMode,
            enableSkinTones: widget.config.skinToneConfig.enabled,
            skinToneIndicatorColor: widget.config.skinToneConfig.indicatorColor,
            onEmojiSelected: () =>
                _onEmojiSelected(categoryEmoji.category, emoji),
            onSkinToneDialogRequested: (emojiBoxPosition) =>
                _openSkinToneDialog(
                  linkKey: linkKey,
                  emojiBoxPosition: emojiBoxPosition,
                  emoji: emoji,
                  emojiSize: emojiSize,
                  emojiBoxSize: emojiBoxSize,
                  categoryEmoji: categoryEmoji,
                ),
          ),
        );
      },
    );
  }

  Widget _addSkinToneTargetIfAvailable({
    required bool hasSkinTone,
    required String linkKey,
    required Widget child,
  }) {
    if (!hasSkinTone) return child;
    final link = _links.putIfAbsent(linkKey, LayerLink.new);
    return CompositedTransformTarget(link: link, child: child);
  }

  void _openSkinToneDialog({
    required String linkKey,
    required Offset emojiBoxPosition,
    required Emoji emoji,
    required double emojiSize,
    required double emojiBoxSize,
    required CategoryEmoji categoryEmoji,
  }) {
    _closeSkinToneOverlay();
    if (!emoji.hasSkinTone || !widget.config.skinToneConfig.enabled) {
      return;
    }

    final skinTonesEmoji = SkinTone.values
        .map((skinTone) => _emojiPickerUtils.applySkinTone(emoji, skinTone))
        .toList();
    final left = _calculateLeftOffset(emojiBoxSize, emojiBoxPosition, context);

    _overlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        child: CompositedTransformFollower(
          link: _links[linkKey]!,
          offset: Offset(left, -emojiBoxSize - 8.0),
          showWhenUnlinked: false,
          child: TapRegion(
            onTapOutside: (_) => _closeSkinToneOverlay(),
            child: Material(
              elevation: 4.0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                color: widget.config.skinToneConfig.dialogBackgroundColor,
                child: Row(
                  children: [
                    _GeneratedEmojiCell(
                      emoji: emoji,
                      emojiSize: emojiSize,
                      emojiBoxSize: emojiBoxSize,
                      buttonMode: widget.config.emojiViewConfig.buttonMode,
                      enableSkinTones: false,
                      skinToneIndicatorColor:
                          widget.config.skinToneConfig.indicatorColor,
                      onEmojiSelected: () =>
                          _onEmojiSelected(categoryEmoji.category, emoji),
                    ),
                    ...skinTonesEmoji.map(
                      (skinToneEmoji) => _GeneratedEmojiCell(
                        emoji: skinToneEmoji,
                        emojiSize: emojiSize,
                        emojiBoxSize: emojiBoxSize,
                        buttonMode: widget.config.emojiViewConfig.buttonMode,
                        enableSkinTones: false,
                        skinToneIndicatorColor:
                            widget.config.skinToneConfig.indicatorColor,
                        onEmojiSelected: () => _onEmojiSelected(
                          categoryEmoji.category,
                          skinToneEmoji,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlay!);
  }

  double _calculateLeftOffset(
    double emojiBoxSize,
    Offset emojiBoxPosition,
    BuildContext context,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    var left = -2.5 * emojiBoxSize;

    if (emojiBoxPosition.dx - 1 * emojiBoxSize < 0) {
      left += 2.5 * emojiBoxSize;
    } else if (emojiBoxPosition.dx - 2 * emojiBoxSize < 0) {
      left += 1.5 * emojiBoxSize;
    } else if (emojiBoxPosition.dx - 3 * emojiBoxSize < 0) {
      left += 0.5 * emojiBoxSize;
    } else if (emojiBoxPosition.dx + 2 * emojiBoxSize > screenWidth) {
      left -= 2.5 * emojiBoxSize;
    } else if (emojiBoxPosition.dx + 3 * emojiBoxSize > screenWidth) {
      left -= 1.5 * emojiBoxSize;
    } else if (emojiBoxPosition.dx + 4 * emojiBoxSize > screenWidth) {
      left -= 0.5 * emojiBoxSize;
    }
    return left;
  }

  void _onEmojiSelected(Category? category, Emoji emoji) {
    widget.state.onEmojiSelected(category, emoji);
    _closeSkinToneOverlay();
  }

  void _closeSkinToneOverlay() {
    _overlay?.remove();
    _overlay = null;
  }
}

class _GeneratedEmojiCell extends StatelessWidget {
  const _GeneratedEmojiCell({
    required this.emoji,
    required this.emojiSize,
    required this.emojiBoxSize,
    required this.buttonMode,
    required this.enableSkinTones,
    required this.skinToneIndicatorColor,
    required this.onEmojiSelected,
    this.onSkinToneDialogRequested,
  });

  final Emoji emoji;
  final double emojiSize;
  final double emojiBoxSize;
  final ButtonMode buttonMode;
  final bool enableSkinTones;
  final Color skinToneIndicatorColor;
  final VoidCallback onEmojiSelected;
  final ValueChanged<Offset>? onSkinToneDialogRequested;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: emojiBoxSize,
      height: emojiBoxSize,
      child: _buildButtonWidget(
        context: context,
        child: FittedBox(fit: BoxFit.scaleDown, child: _buildEmojiContent()),
      ),
    );
  }

  Widget _buildButtonWidget({
    required BuildContext context,
    required Widget child,
  }) {
    switch (buttonMode) {
      case ButtonMode.MATERIAL:
        return MaterialButton(
          onPressed: onEmojiSelected,
          onLongPress: () => _notifySkinToneDialogRequested(context),
          elevation: 0,
          highlightElevation: 0,
          padding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          child: child,
        );
      case ButtonMode.CUPERTINO:
        return GestureDetector(
          onLongPress: () => _notifySkinToneDialogRequested(context),
          child: CupertinoButton(
            onPressed: onEmojiSelected,
            padding: EdgeInsets.zero,
            alignment: Alignment.center,
            child: child,
          ),
        );
      case ButtonMode.NONE:
        return GestureDetector(
          onTap: onEmojiSelected,
          onLongPress: () => _notifySkinToneDialogRequested(context),
          child: Center(child: child),
        );
    }
  }

  void _notifySkinToneDialogRequested(BuildContext context) {
    final callback = onSkinToneDialogRequested;
    if (callback == null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    callback(renderBox.localToGlobal(Offset.zero));
  }

  Widget _buildEmojiContent() {
    final emojiWidget = EmojiGlyph(emoji.emoji, dimension: emojiSize);

    if (!emoji.hasSkinTone ||
        !enableSkinTones ||
        onSkinToneDialogRequested == null) {
      return emojiWidget;
    }

    return Container(
      decoration: TriangleDecoration(color: skinToneIndicatorColor, size: 8.0),
      child: emojiWidget,
    );
  }
}
