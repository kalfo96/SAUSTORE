import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A label/value pair that adapts to narrow widths.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    this.showDivider = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
        ],
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    final valueWidget =
        trailing ??
        Text(
          value,
          textAlign: TextAlign.end,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: valueColor ?? theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        );

    final row = LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth.isFinite && constraints.maxWidth < 320;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelWidget,
              const SizedBox(height: AppSpacing.xs),
              Align(alignment: Alignment.centerLeft, child: valueWidget),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: AppSpacing.md),
            Flexible(child: valueWidget),
          ],
        );
      },
    );

    return Semantics(
      container: true,
      label: '$label, $value',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: padding, child: row),
          if (showDivider) const Divider(),
        ],
      ),
    );
  }
}
