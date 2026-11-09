import 'package:flutter/material.dart';

import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/status_pill.dart';

String formatMoney(
  InventoryController controller,
  int amount, {
  bool compact = false,
}) {
  final settings = controller.settings;
  if (compact) {
    return AppFormatters.compactMoney(
      amount,
      symbol: settings.currencySymbol,
      decimalDigits: settings.currencyDecimalDigits,
    );
  }
  return AppFormatters.money(
    amount,
    symbol: settings.currencySymbol,
    decimalDigits: settings.currencyDecimalDigits,
  );
}

int parseMoneyInput(String raw, int decimalDigits) {
  final value = raw.trim().replaceAll(',', '');
  if (value.isEmpty) return 0;
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
    throw const FormatException('Invalid money value');
  }
  final parts = value.split('.');
  if (parts.length > 1 && parts[1].length > decimalDigits) {
    throw const FormatException('Too many decimal places');
  }
  var scale = 1;
  for (var index = 0; index < decimalDigits; index++) {
    scale *= 10;
  }
  final whole = int.parse(parts.first) * scale;
  if (decimalDigits == 0) return whole;
  final fraction = parts.length == 1
      ? 0
      : int.parse(parts[1].padRight(decimalDigits, '0'));
  return whole + fraction;
}

String moneyInputValue(int minor, int decimalDigits) {
  if (decimalDigits == 0) return minor.toString();
  var scale = 1;
  for (var index = 0; index < decimalDigits; index++) {
    scale *= 10;
  }
  final whole = minor ~/ scale;
  final fraction = (minor % scale).toString().padLeft(decimalDigits, '0');
  return '$whole.$fraction';
}

StatusPill productStatusPill(BuildContext context, Product product) {
  final semantic = context.semanticColors;
  if (product.isArchived) {
    return StatusPill(
      label: 'Archived',
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      icon: Icons.archive_outlined,
      compact: true,
    );
  }
  if (product.isOutOfStock) {
    return StatusPill(
      label: 'Out of stock',
      color: Theme.of(context).colorScheme.error,
      icon: Icons.error_outline,
      compact: true,
    );
  }
  if (product.isLowStock) {
    return StatusPill(
      label: 'Low stock',
      color: semantic.warning,
      icon: Icons.warning_amber_rounded,
      compact: true,
    );
  }
  return StatusPill(
    label: 'In stock',
    color: semantic.success,
    icon: Icons.check_circle_outline,
    compact: true,
  );
}

Color movementColor(BuildContext context, StockMovement movement) {
  if (movement.quantityDelta > 0) return context.semanticColors.success;
  if (movement.quantityDelta < 0) return Theme.of(context).colorScheme.error;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

IconData movementIcon(StockMovementType type) => switch (type) {
  StockMovementType.opening => Icons.flag_outlined,
  StockMovementType.restock => Icons.add_box_outlined,
  StockMovementType.sale => Icons.shopping_bag_outlined,
  StockMovementType.departmentIssue => Icons.local_shipping_outlined,
  StockMovementType.adjustment => Icons.tune,
  StockMovementType.reversal => Icons.undo,
};

class ProductAvatar extends StatelessWidget {
  const ProductAvatar({super.key, required this.product, this.size = 48});

  final Product product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${product.name} product',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(size * .28),
        ),
        child: Text(
          AppFormatters.initials(product.name),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class MovementListTile extends StatelessWidget {
  const MovementListTile({super.key, required this.movement, this.onTap});

  final StockMovement movement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = movementColor(context, movement);
    final delta = movement.quantityDelta > 0
        ? '+${AppFormatters.quantity(movement.quantityDelta)}'
        : AppFormatters.quantity(movement.quantityDelta);
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(movementIcon(movement.type), color: color, size: 21),
      ),
      title: Text(movement.productName),
      subtitle: Text(
        '${movement.type.label}'
        '${movement.department == null ? '' : ' | ${movement.department!.label}'}\n'
        '${AppFormatters.date(movement.occurredAt.toLocal(), includeWeekday: true)}'
        '${movement.actorName == null ? '' : '\nBy ${movement.actorName}'}'
        '${_isDifferentDay(movement.occurredAt, movement.recordedAt) ? '\nEntered ${AppFormatters.dateTime(movement.recordedAt.toLocal())}' : ''}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            delta,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${movement.quantityAfter} after',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static bool _isDifferentDay(DateTime first, DateTime second) {
    return !DateUtils.isSameDay(first.toLocal(), second.toLocal());
  }
}
