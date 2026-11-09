import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An accessible integer stepper for quantities.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.step = 1,
    this.enabled = true,
    this.compact = false,
    this.label = 'Quantity',
  }) : assert(step > 0, 'step must be greater than zero'),
       assert(max == null || max >= min, 'max must be greater than min');

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int? max;
  final int step;
  final bool enabled;
  final bool compact;
  final String label;

  bool get _canDecrease => enabled && onChanged != null && value > min;
  bool get _canIncrease =>
      enabled && onChanged != null && (max == null || value < max!);

  void _decrease() {
    if (!_canDecrease) return;
    onChanged!(value - step < min ? min : value - step);
  }

  void _increase() {
    if (!_canIncrease) return;
    final next = value + step;
    onChanged!(max != null && next > max! ? max! : next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    final height = compact ? 40.0 : 46.0;

    return Semantics(
      label: label,
      value: '$value',
      increasedValue: _canIncrease ? '${value + step}' : null,
      decreasedValue: _canDecrease ? '${value - step}' : null,
      onIncrease: _canIncrease ? _increase : null,
      onDecrease: _canDecrease ? _decrease : null,
      enabled: enabled,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              tooltip: 'Decrease $label',
              onPressed: _canDecrease ? _decrease : null,
              compact: compact,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: compact ? 42 : 50),
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              tooltip: 'Increase $label',
              onPressed: _canIncrease ? _increase : null,
              compact: compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.compact,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: compact ? 18 : 20),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 38 : 44,
        height: compact ? 38 : 44,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
