import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A responsive page title with optional supporting text and actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.leading,
    this.action,
    this.actions = const [],
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final Widget? leading;
  final Widget? action;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final actionWidgets = <Widget>[...actions, ?action];

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth.isFinite && constraints.maxWidth < 560;
          final titleBlock = _TitleBlock(
            title: title,
            subtitle: subtitle,
            eyebrow: eyebrow,
          );

          if (isCompact && actionWidgets.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeaderTitleRow(leading: leading, child: titleBlock),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.start,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: actionWidgets,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(child: titleBlock),
              if (actionWidgets.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  flex: 0,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: actionWidgets,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HeaderTitleRow extends StatelessWidget {
  const _HeaderTitleRow({required this.leading, required this.child});

  final Widget? leading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(child: child),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.subtitle,
    required this.eyebrow,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow case final eyebrow?) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 2,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    eyebrow.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: MediaQuery.sizeOf(context).width < 600 ? 27 : 32,
              letterSpacing: -1,
            ),
          ),
          if (subtitle case final subtitle?) ...[
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
