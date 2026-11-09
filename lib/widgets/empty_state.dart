import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A calm empty or filtered state with an optional primary action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.actionLabel,
    this.actionIcon = Icons.add_rounded,
    this.onAction,
    this.compact = false,
    this.padding,
  }) : assert(
         action == null || (actionLabel == null && onAction == null),
         'Use either action or actionLabel/onAction, not both.',
       ),
       assert(
         (actionLabel == null) == (onAction == null),
         'actionLabel and onAction must be provided together.',
       );

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final bool compact;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionWidget =
        action ??
        (onAction == null
            ? null
            : FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon),
                label: Text(actionLabel!),
              ));

    return Semantics(
      container: true,
      label: '$title. $message',
      child: Center(
        child: SingleChildScrollView(
          padding:
              padding ??
              EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: compact ? AppSpacing.lg : AppSpacing.xxl,
              ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: compact ? 80 : 100,
                  height: compact ? 80 : 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.09,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: compact ? 60 : 76,
                        height: compact ? 60 : 76,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primaryContainer,
                              theme.colorScheme.primaryContainer.withValues(
                                alpha: 0.45,
                              ),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(
                            compact ? 22 : 27,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          icon,
                          size: compact ? 28 : 34,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Positioned(
                        right: compact ? 5 : 8,
                        top: compact ? 5 : 8,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.surfaceContainerLowest,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (actionWidget != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  actionWidget,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
