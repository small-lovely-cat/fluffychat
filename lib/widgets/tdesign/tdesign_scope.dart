import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class TDesignScope extends StatelessWidget {
  final Widget child;

  const TDesignScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    TTheme.needMultiTheme();
    final baseTheme = TThemeData.defaultData();
    return TTheme(data: baseTheme, systemData: Theme.of(context), child: child);
  }
}

class TDesignSectionTitle extends StatelessWidget {
  final String title;

  const TDesignSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class TDesignSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const TDesignSectionCard({
    required this.child,
    this.margin,
    this.padding,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
