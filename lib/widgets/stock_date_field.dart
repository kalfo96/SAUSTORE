import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// A calendar date, separate from the timestamp when an entry is saved.
class StockDateField extends StatelessWidget {
  const StockDateField({
    super.key,
    required this.value,
    required this.label,
    required this.helperText,
    this.onChanged,
  });

  final DateTime value;
  final String label;
  final String helperText;
  final ValueChanged<DateTime>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$label-${value.toIso8601String()}'),
      initialValue: AppFormatters.date(value.toLocal(), includeWeekday: true),
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 3,
        prefixIcon: const Icon(Icons.event_outlined),
        suffixIcon: onChanged == null
            ? const Icon(Icons.lock_outline, size: 18)
            : const Icon(Icons.calendar_month_outlined),
      ),
      onTap: onChanged == null
          ? null
          : () async {
              final today = DateUtils.dateOnly(DateTime.now());
              final selected = await showDatePicker(
                context: context,
                initialDate: DateUtils.dateOnly(value.toLocal()).isAfter(today)
                    ? today
                    : DateUtils.dateOnly(value.toLocal()),
                firstDate: DateTime(1900),
                lastDate: today,
                helpText: label,
              );
              if (selected != null && context.mounted) onChanged!(selected);
            },
    );
  }
}
