import 'package:flutter/material.dart';

class TThemeData {
  final ThemeData light;
  final ThemeData? dark;
  final Color componentStrokeColor;
  final double spacer4;
  final double spacer12;

  const TThemeData({
    required this.light,
    required this.dark,
    required this.componentStrokeColor,
    this.spacer4 = 4,
    this.spacer12 = 12,
  });

  factory TThemeData.defaultData() {
    final light = ThemeData.light(useMaterial3: true);
    final dark = ThemeData.dark(useMaterial3: true);
    return TThemeData(
      light: light,
      dark: dark,
      componentStrokeColor: light.colorScheme.outlineVariant,
    );
  }
}

class TTheme extends InheritedWidget {
  final TThemeData data;
  final ThemeData systemData;

  const TTheme({
    super.key,
    required this.data,
    required this.systemData,
    required super.child,
  });

  static void needMultiTheme() {}

  static TThemeData of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<TTheme>();
    if (inherited != null) return inherited.data;
    final theme = Theme.of(context);
    return TThemeData(
      light: theme,
      dark: theme,
      componentStrokeColor: theme.colorScheme.outlineVariant,
    );
  }

  @override
  bool updateShouldNotify(TTheme oldWidget) => data != oldWidget.data;
}

enum TButtonType { fill, text, outline, ghost }

enum TButtonTheme { primary, danger }

enum TButtonShape { round, circle }

class TButton extends StatelessWidget {
  final String? text;
  final Object? icon;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final TButtonType type;
  final TButtonTheme? theme;
  final TButtonShape? shape;
  final bool isBlock;

  const TButton({
    super.key,
    this.text,
    this.icon,
    this.onTap,
    this.width,
    this.height,
    this.type = TButtonType.fill,
    this.theme,
    this.shape,
    this.isBlock = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = theme == TButtonTheme.danger;
    final baseColor = danger ? scheme.error : scheme.primary;
    final foreground = danger ? scheme.onError : scheme.onPrimary;
    final rounded = shape == TButtonShape.circle
        ? const CircleBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              shape == TButtonShape.round ? 999 : 14,
            ),
          );
    final child = _buildChild();
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(width ?? (isBlock ? double.infinity : 0), height ?? 40),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(rounded),
    );

    Widget button;
    switch (type) {
      case TButtonType.text:
      case TButtonType.ghost:
        button = TextButton(
          onPressed: onTap,
          style: style.copyWith(
            foregroundColor: WidgetStatePropertyAll(baseColor),
          ),
          child: child,
        );
        break;
      case TButtonType.outline:
        button = OutlinedButton(
          onPressed: onTap,
          style: style.copyWith(
            foregroundColor: WidgetStatePropertyAll(baseColor),
            side: WidgetStatePropertyAll(BorderSide(color: baseColor)),
          ),
          child: child,
        );
        break;
      case TButtonType.fill:
        button = ElevatedButton(
          onPressed: onTap,
          style: style.copyWith(
            backgroundColor: WidgetStatePropertyAll(baseColor),
            foregroundColor: WidgetStatePropertyAll(foreground),
          ),
          child: child,
        );
        break;
    }

    if (width != null || isBlock) {
      return SizedBox(width: width ?? double.infinity, height: height, child: button);
    }
    return SizedBox(height: height, child: button);
  }

  Widget _buildChild() {
    final children = <Widget>[];
    if (icon != null) {
      children.add(
        icon is Widget ? icon as Widget : Icon(icon as IconData, size: 18),
      );
    }
    if (text != null && text!.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(Text(text!));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class TIcons {
  static const IconData camera = Icons.camera_alt_outlined;
  static const IconData edit_1 = Icons.edit_outlined;
  static const IconData share = Icons.share_outlined;
  static const IconData brush = Icons.brush_outlined;
  static const IconData notification = Icons.notifications_outlined;
  static const IconData mobile = Icons.smartphone_outlined;
  static const IconData chat_bubble = Icons.chat_bubble_outline;
  static const IconData chat_bubble_add = Icons.add_comment_outlined;
  static const IconData secured = Icons.verified_user_outlined;
  static const IconData internet = Icons.language_outlined;
  static const IconData lock_on = Icons.lock_outline;
  static const IconData info_circle = Icons.info_outline;
  static const IconData logout = Icons.logout;
  static const IconData chevron_left = Icons.chevron_left;
  static const IconData chevron_right = Icons.chevron_right;
  static const IconData arrow_down = Icons.keyboard_arrow_down;
  static const IconData more = Icons.more_horiz;
}

typedef TCellClick = void Function(TCell cell);

class TCell extends StatelessWidget {
  final String? title;
  final String? description;
  final Widget? descriptionWidget;
  final Widget? titleWidget;
  final Widget? leftIconWidget;
  final Widget? noteWidget;
  final Widget? rightIconWidget;
  final Widget? imageWidget;
  final bool arrow;
  final bool showBottomBorder;
  final double? height;
  final TCellClick? onClick;
  final TCellClick? onLongPress;

  const TCell({
    super.key,
    this.title,
    this.description,
    this.descriptionWidget,
    this.titleWidget,
    this.leftIconWidget,
    this.noteWidget,
    this.rightIconWidget,
    this.imageWidget,
    this.arrow = false,
    this.showBottomBorder = false,
    this.height,
    this.onClick,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: showBottomBorder
            ? Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          if (imageWidget != null) ...[
            imageWidget!,
            const SizedBox(width: 12),
          ],
          if (leftIconWidget != null) ...[
            leftIconWidget!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleWidget ??
                    Text(
                      title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                if (descriptionWidget != null) ...[
                  const SizedBox(height: 4),
                  descriptionWidget!,
                ] else if (description != null && description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (noteWidget != null) noteWidget!,
          if (rightIconWidget != null) rightIconWidget!,
          if (arrow) ...[
            const SizedBox(width: 4),
            Icon(TIcons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ],
      ),
    );
    return InkWell(
      onTap: onClick == null ? null : () => onClick!(this),
      onLongPress: onLongPress == null ? null : () => onLongPress!(this),
      child: body,
    );
  }
}

class TSwitch extends StatelessWidget {
  final bool isOn;
  final bool Function(bool value)? onChanged;

  const TSwitch({super.key, required this.isOn, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: isOn,
      onChanged: onChanged == null ? null : (value) => onChanged!(value),
    );
  }
}

enum TFabTheme { primary, light }

enum TFabSize { medium }

class TFab extends StatelessWidget {
  final Object? icon;
  final String? text;
  final VoidCallback? onClick;
  final TFabTheme theme;
  final TFabSize size;

  const TFab({
    super.key,
    this.icon,
    this.text,
    this.onClick,
    this.theme = TFabTheme.primary,
    this.size = TFabSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundColor = theme == TFabTheme.light ? scheme.surface : scheme.primary;
    final foregroundColor = theme == TFabTheme.light ? scheme.primary : scheme.onPrimary;
    if (text != null && text!.isNotEmpty) {
      return FloatingActionButton.extended(
        onPressed: onClick,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        icon: icon is Widget ? icon as Widget : Icon(icon as IconData),
        label: Text(text!),
      );
    }
    return FloatingActionButton(
      onPressed: onClick,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      child: icon is Widget ? icon as Widget : Icon(icon as IconData),
    );
  }
}

class TSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeHolder;
  final String? action;
  final bool needCancel;
  final bool autoHeight;
  final bool mediumStyle;
  final Color? backgroundColor;
  final VoidCallback? onInputClick;
  final void Function(String value)? onSubmitted;
  final void Function(String value)? onTextChanged;
  final void Function(String value)? onActionClick;

  const TSearchBar({
    super.key,
    this.controller,
    this.focusNode,
    this.placeHolder,
    this.action,
    this.needCancel = false,
    this.autoHeight = false,
    this.mediumStyle = false,
    this.backgroundColor,
    this.onInputClick,
    this.onSubmitted,
    this.onTextChanged,
    this.onActionClick,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      onTap: onInputClick,
      onChanged: onTextChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: placeHolder,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
    if (!needCancel) return field;
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => onActionClick?.call(controller?.text ?? ''),
          child: Text(action ?? ''),
        ),
      ],
    );
  }
}

class TNavBarItem {
  final Widget? customWidget;

  const TNavBarItem({this.customWidget});
}

class TNavBar extends StatelessWidget {
  final String title;
  final bool useDefaultBack;
  final List<TNavBarItem>? leftBarItems;

  const TNavBar({
    super.key,
    required this.title,
    this.useDefaultBack = true,
    this.leftBarItems,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kToolbarHeight,
      child: Row(
        children: [
          const SizedBox(width: 8),
          if (leftBarItems != null && leftBarItems!.isNotEmpty)
            ...leftBarItems!.map((item) => item.customWidget ?? const SizedBox.shrink())
          else if (useDefaultBack)
            const BackButton(),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
