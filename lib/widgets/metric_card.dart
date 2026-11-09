import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'section_card.dart';

/// A compact summary card for inventory, revenue, and activity metrics.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.helperText,
    this.trend,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? helperText;
  final String? trend;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;

    return SectionCard(
      onTap: onTap,
      semanticLabel: semanticLabel ?? '$label, $value',
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.2 : 0.1,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: accent, size: 19),
              ),
              if (trend case final trend?) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.08,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    trend,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ] else ...[
                const Spacer(),
                Container(
                  width: 28,
                  height: 3,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 29,
              letterSpacing: -1.1,
              height: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (helperText case final helperText?) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              helperText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
