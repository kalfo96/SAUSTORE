import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A concise semantic status label.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
    this.tooltip,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pill = Semantics(
      label: label,
      container: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 11,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.18 : 0.075),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.3 : 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 13 : 15, color: color),
              SizedBox(width: compact ? AppSpacing.xxs : 6),
            ] else ...[
              Container(
                width: compact ? 5 : 6,
                height: compact ? 5 : 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: compact ? 10 : 11,
                  letterSpacing: 0.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (tooltip == null) return pill;
    return Tooltip(message: tooltip!, child: pill);
  }
}
