import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A low-elevation bordered surface used to group related content.
class SectionCard extends StatefulWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppRadii.large,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final String? semanticLabel;

  @override
  State<SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<SectionCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(widget.borderRadius);
    final interactive = widget.onTap != null;
    final emphasized = interactive && (_hovered || _focused);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    Widget content = Padding(padding: widget.padding, child: widget.child);

    if (interactive) {
      content = InkWell(
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovered = value),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        onFocusChange: (value) => setState(() => _focused = value),
        hoverColor: scheme.primary.withValues(alpha: 0.035),
        focusColor: scheme.primary.withValues(alpha: 0.06),
        borderRadius: radius,
        child: content,
      );
    }

    content = Material(
      color: widget.backgroundColor ?? scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color:
              widget.borderColor ??
              (emphasized
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outlineVariant.withValues(
                      alpha: isDark ? 0.6 : 0.8,
                    )),
          width: _focused ? 1.5 : 1,
        ),
      ),
      child: content,
    );

    if (widget.semanticLabel != null || interactive) {
      content = Semantics(
        label: widget.semanticLabel,
        button: interactive,
        container: true,
        child: content,
      );
    }

    return Padding(
      padding: widget.margin,
      child: AnimatedScale(
        scale: _pressed && interactive && !reduceMotion ? 0.988 : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF142B35,
                ).withValues(alpha: isDark ? 0 : (emphasized ? 0.075 : 0.035)),
                blurRadius: emphasized ? 24 : 14,
                offset: Offset(0, emphasized ? 7 : 3),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Heading for a card or page section, with an optional trailing control.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle case final subtitle?) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
