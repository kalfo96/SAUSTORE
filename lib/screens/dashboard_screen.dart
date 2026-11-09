import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import 'screen_helpers.dart';

/// A live operations overview. All summaries come from saved stock and usage.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.onAddProduct,
    required this.onOpenInventory,
    required this.onOpenSale,
    required this.onOpenProduct,
    required this.onOpenDepartment,
    required this.onOpenReports,
    this.onReceiveDelivery,
  });

  final InventoryController controller;
  final VoidCallback onAddProduct;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenSale;
  final ValueChanged<Product> onOpenProduct;
  final ValueChanged<HotelDepartment> onOpenDepartment;
  final VoidCallback onOpenReports;
  final VoidCallback? onReceiveDelivery;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  HotelDepartment? _usageDepartment;
  int _selectedDay = 6;
  bool _showAllDepartments = false;

  InventoryController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final days = List<DateTime>.generate(
          7,
          (index) => DateTime(today.year, today.month, today.day - 6 + index),
        );
        final issues = _controller.departmentIssues;
        final todaysIssues = issues.where(
          (issue) => _sameDay(issue.issuedAt.toLocal(), today),
        );
        final attention = <Product>[
          ..._controller.outOfStockProducts,
          ..._controller.lowStockProducts,
        ];
        final visibleDepartments = HotelDepartment.values.where(
          (department) =>
              _showAllDepartments ||
              department == HotelDepartment.kitchen ||
              _controller.activeProducts.any(
                (product) => product.department == department,
              ) ||
              todaysIssues.any((issue) => issue.department == department),
        );
        final usage = days
            .map((day) {
              final entries = issues.where(
                (issue) =>
                    _sameDay(issue.issuedAt.toLocal(), day) &&
                    (_usageDepartment == null ||
                        issue.department == _usageDepartment),
              );
              return _DayUsage(
                day,
                entries.fold<int>(0, (total, issue) => total + issue.quantity),
                entries.fold<int>(
                  0,
                  (total, issue) => total + issue.valueMinor,
                ),
              );
            })
            .toList(growable: false);

        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = constraints.maxWidth < 600 ? 16.0 : 28.0;
              return SingleChildScrollView(
                key: const PageStorageKey<String>('operations-dashboard'),
                padding: EdgeInsets.fromLTRB(inset, 24, inset, 36),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1260),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _OverviewHero(
                          controller: _controller,
                          today: today,
                          attentionCount: attention.length,
                          onAddProduct: widget.onAddProduct,
                          onOpenInventory: widget.onOpenInventory,
                        ),
                        const SizedBox(height: 20),
                        _ResponsiveTiles(
                          minimumWidth: 148,
                          maximumColumns: 4,
                          children: [
                            MetricCard(
                              label: 'Units on hand',
                              value: AppFormatters.quantity(
                                _controller.totalStockUnits,
                              ),
                              icon: Icons.inventory_2_outlined,
                              helperText:
                                  '${_controller.activeProductCount} stock items',
                              onTap: widget.onOpenInventory,
                            ),
                            MetricCard(
                              label: 'Stock at cost',
                              value: formatMoney(
                                _controller,
                                _controller.inventoryCostValueMinor,
                                compact: true,
                              ),
                              icon: Icons.account_balance_wallet_outlined,
                              helperText: 'Current on-hand value',
                              onTap: widget.onOpenInventory,
                            ),
                            MetricCard(
                              label: 'Used today',
                              value: AppFormatters.quantity(
                                todaysIssues.fold<int>(
                                  0,
                                  (total, issue) => total + issue.quantity,
                                ),
                              ),
                              icon: Icons.restaurant_outlined,
                              helperText: 'Across all departments',
                              color: context.semanticColors.info,
                              onTap: widget.onOpenReports,
                            ),
                            MetricCard(
                              label: 'Sales today',
                              value: formatMoney(
                                _controller,
                                _controller.todaysRevenueMinor,
                                compact: true,
                              ),
                              icon: Icons.point_of_sale_outlined,
                              helperText:
                                  '${_controller.todaysSalesCount} completed sales',
                              color: context.semanticColors.warning,
                              onTap: widget.onOpenSale,
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        LayoutBuilder(
                          builder: (context, sectionConstraints) {
                            final chart = _usageChart(context, usage);
                            final actions = _quickActions(context);
                            if (sectionConstraints.maxWidth < 980 ||
                                _textScale(context) > 1.35) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  chart,
                                  const SizedBox(height: 16),
                                  actions,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 7, child: chart),
                                const SizedBox(width: 20),
                                Expanded(flex: 4, child: actions),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 30),
                        _DashboardHeading(
                          title: 'Every team, in one place',
                          subtitle: 'Assigned stock and today’s consumption.',
                          actionLabel: 'View stock',
                          onAction: widget.onOpenInventory,
                        ),
                        const SizedBox(height: 14),
                        _ResponsiveTiles(
                          minimumWidth: 200,
                          maximumColumns: 5,
                          children: visibleDepartments
                              .map((department) {
                                final products = _controller.activeProducts
                                    .where(
                                      (product) =>
                                          product.department == department,
                                    );
                                final units = products.fold<int>(
                                  0,
                                  (total, product) => total + product.quantity,
                                );
                                final used = todaysIssues
                                    .where(
                                      (issue) => issue.department == department,
                                    )
                                    .fold<int>(
                                      0,
                                      (total, issue) => total + issue.quantity,
                                    );
                                final alerts = products
                                    .where(
                                      (product) =>
                                          product.isLowStock ||
                                          product.isOutOfStock,
                                    )
                                    .length;
                                return _DepartmentTile(
                                  department: department,
                                  units: units,
                                  used: used,
                                  productCount: products.length,
                                  alerts: alerts,
                                  onTap: () =>
                                      widget.onOpenDepartment(department),
                                );
                              })
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const ValueKey<String>(
                              'dashboard-toggle-teams',
                            ),
                            onPressed: () => setState(
                              () => _showAllDepartments = !_showAllDepartments,
                            ),
                            icon: Icon(
                              _showAllDepartments
                                  ? Icons.unfold_less_rounded
                                  : Icons.unfold_more_rounded,
                            ),
                            label: Text(
                              _showAllDepartments
                                  ? 'Show fewer teams'
                                  : 'Explore all ${HotelDepartment.values.length} departments',
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        LayoutBuilder(
                          builder: (context, sectionConstraints) {
                            final alerts = _attentionPanel(context, attention);
                            final activity = _activityPanel(context);
                            if (sectionConstraints.maxWidth < 880 ||
                                _textScale(context) > 1.35) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  alerts,
                                  const SizedBox(height: 20),
                                  activity,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: alerts),
                                const SizedBox(width: 20),
                                Expanded(child: activity),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _usageChart(BuildContext context, List<_DayUsage> days) {
    final theme = Theme.of(context);
    final selected = days[_selectedDay];
    final weekTotal = days.fold<int>(0, (total, day) => total + day.units);
    final maximum = math.max(
      1,
      days.fold<int>(0, (a, b) => math.max(a, b.units)),
    );
    return SectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DashboardHeading(
            title: 'The rhythm of your stock',
            subtitle: 'Department usage · Last seven days',
            actionLabel: 'Reports',
            onAction: widget.onOpenReports,
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Usage department',
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<HotelDepartment?>(
                key: const ValueKey<String>('dashboard-usage-department'),
                value: _usageDepartment,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<HotelDepartment?>(
                    value: null,
                    child: Text('All departments'),
                  ),
                  ...HotelDepartment.values.map(
                    (department) => DropdownMenuItem<HotelDepartment?>(
                      value: department,
                      child: Text(department.label),
                    ),
                  ),
                ],
                onChanged: (department) =>
                    setState(() => _usageDepartment = department),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${AppFormatters.quantity(weekTotal)} units consumed in the last 7 days',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Stack(
            children: [
              Positioned.fill(
                bottom: 34,
                child: CustomPaint(
                  painter: _ChartGridPainter(theme.colorScheme.outlineVariant),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List<Widget>.generate(days.length, (index) {
                  final day = days[index];
                  final active = index == _selectedDay;
                  final barHeight = math.max(4.0, 116 * day.units / maximum);
                  return Expanded(
                    child: Semantics(
                      button: true,
                      selected: active,
                      label:
                          '${AppFormatters.date(day.day, includeWeekday: true)}, '
                          '${day.units} units consumed, '
                          '${formatMoney(_controller, day.cost)} consumption cost',
                      child: Tooltip(
                        message:
                            '${AppFormatters.date(day.day)}: ${day.units} units',
                        child: InkWell(
                          key: ValueKey<String>('dashboard-usage-day-$index'),
                          onTap: () => setState(() => _selectedDay = index),
                          borderRadius: BorderRadius.circular(10),
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 142 + 16 * _textScale(context),
                                  child: Stack(
                                    alignment: Alignment.bottomCenter,
                                    children: [
                                      AnimatedContainer(
                                        duration: _motionDuration(context),
                                        height: barHeight,
                                        width: 22,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
                                          color: active
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.primary
                                                    .withValues(alpha: .2),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: barHeight + 6,
                                        left: 0,
                                        right: 0,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            AppFormatters.quantity(day.units),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: active
                                                      ? theme
                                                            .colorScheme
                                                            .primary
                                                      : theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  fontWeight: active
                                                      ? FontWeight.w800
                                                      : FontWeight.w500,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  const [
                                    'Mo',
                                    'Tu',
                                    'We',
                                    'Th',
                                    'Fr',
                                    'Sa',
                                    'Su',
                                  ][day.day.weekday - 1],
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: active
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontWeight: active
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Semantics(
              key: const ValueKey<String>('dashboard-selected-usage'),
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppFormatters.date(selected.day, includeWeekday: true),
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${AppFormatters.quantity(selected.units)} units used · '
                    '${formatMoney(_controller, selected.cost)} at cost',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            weekTotal == 0
                ? 'No usage recorded in this period. Record what a team uses to start its story here.'
                : 'Tap a day to explore. Consumption is valued at the recorded stock cost, not sales revenue.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DashboardHeading(
            title: 'Make your next move',
            subtitle: 'Small actions. A well-run hotel.',
          ),
          const SizedBox(height: 18),
          _ActionTile(
            title: 'Receive a delivery',
            subtitle: 'Choose an item, add stock and its arrival date.',
            icon: Icons.move_to_inbox_outlined,
            onTap: widget.onReceiveDelivery ?? widget.onOpenInventory,
          ),
          const SizedBox(height: 8),
          _ActionTile(
            title: 'Record kitchen usage',
            subtitle: 'Track ingredients used and remaining stock.',
            icon: Icons.restaurant_outlined,
            onTap: () => widget.onOpenDepartment(HotelDepartment.kitchen),
          ),
          const SizedBox(height: 8),
          _ActionTile(
            title: 'Record a sale',
            subtitle: 'A receipt and an automatic stock update.',
            icon: Icons.point_of_sale_outlined,
            onTap: widget.onOpenSale,
          ),
        ],
      ),
    );
  }

  Widget _attentionPanel(BuildContext context, List<Product> products) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DashboardHeading(
            title: 'A little attention',
            subtitle: '${products.length} low or empty stock items',
            actionLabel: 'Inventory',
            onAction: widget.onOpenInventory,
          ),
          const SizedBox(height: 16),
          if (_controller.activeProductCount == 0)
            _EmptyNote(
              icon: Icons.inventory_2_outlined,
              title: 'Your stockroom starts here',
              subtitle:
                  'Add your first stock item, choose its department and record the arrival date.',
              action: TextButton.icon(
                onPressed: widget.onAddProduct,
                icon: const Icon(Icons.add),
                label: const Text('Add first item'),
              ),
            )
          else if (products.isEmpty)
            const _EmptyNote(
              icon: Icons.check_circle_outline,
              title: 'Room to breathe',
              subtitle:
                  'Every active stock item is above its low-stock threshold.',
            )
          else
            ...products
                .take(5)
                .map(
                  (product) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ActionTile(
                      title: product.name,
                      subtitle:
                          '${product.department.label} · '
                          '${product.isOutOfStock ? 'Out of stock' : '${product.quantity} left · alert at ${product.lowStockThreshold}'}',
                      icon: product.isOutOfStock
                          ? Icons.error_outline
                          : Icons.warning_amber_rounded,
                      accent: product.isOutOfStock
                          ? theme.colorScheme.error
                          : context.semanticColors.warning,
                      onTap: () => widget.onOpenProduct(product),
                    ),
                  ),
                ),
          if (products.length > 5)
            TextButton(
              onPressed: widget.onOpenInventory,
              child: Text(
                'View all ${products.length} items needing attention',
              ),
            ),
        ],
      ),
    );
  }

  Widget _activityPanel(BuildContext context) {
    final theme = Theme.of(context);
    final recorded = _controller.movements.toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final movements = recorded.take(4).toList();
    return SectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DashboardHeading(
            title: 'The latest in your stockroom',
            subtitle: 'Receipts, usage and stock changes.',
          ),
          const SizedBox(height: 18),
          if (movements.isEmpty)
            const _EmptyNote(
              icon: Icons.history_rounded,
              title: 'Ready for the first chapter',
              subtitle:
                  'Your stock arrivals and movements will appear here with their exact dates.',
            ),
          ...movements.map((movement) {
            final product = _controller.productById(movement.productId);
            final delta = movement.quantityDelta > 0
                ? '+${AppFormatters.quantity(movement.quantityDelta)}'
                : AppFormatters.quantity(movement.quantityDelta);
            final localDate = movement.occurredAt.toLocal();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ActionTile(
                title: movement.productName,
                subtitle:
                    '${movement.type == StockMovementType.departmentIssue ? 'Department usage' : movement.type.label} · $delta units'
                    '${movement.department == null ? '' : ' · ${movement.department!.label}'}\n'
                    '${AppFormatters.date(localDate)} at ${AppFormatters.time(localDate)}',
                icon: movementIcon(movement.type),
                accent: movement.quantityDelta > 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                onTap: product == null
                    ? null
                    : () => widget.onOpenProduct(product),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _OverviewHero extends StatelessWidget {
  const _OverviewHero({
    required this.controller,
    required this.today,
    required this.attentionCount,
    required this.onAddProduct,
    required this.onOpenInventory,
  });

  final InventoryController controller;
  final DateTime today;
  final int attentionCount;
  final VoidCallback onAddProduct;
  final VoidCallback onOpenInventory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = controller.activeProductCount;
    final healthy = math.max(0, count - attentionCount);
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF102B32), Color(0xFF075C62)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(painter: _CoastalPainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= 690 && _textScale(context) < 1.4;
                  final text = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .12),
                              ),
                            ),
                            child: Text(
                              'HOTEL OPERATIONS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFFB5E8DC),
                                letterSpacing: 1.3,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            AppFormatters.date(today, includeWeekday: true),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFCCE1E2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        '$greeting.\nLet’s make today flow.',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontSize: wide ? 34 : 27,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: -.7,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Every delivery, every department, every detail.\n'
                        'Your hotel stockroom, beautifully in order.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFD1E7E7),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: onAddProduct,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFB5E8DC),
                              foregroundColor: const Color(0xFF123F42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('New stock item'),
                          ),
                          OutlinedButton.icon(
                            onPressed: onOpenInventory,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: .4),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                            ),
                            icon: const Icon(
                              Icons.inventory_2_outlined,
                              size: 19,
                            ),
                            label: const Text('Explore stock'),
                          ),
                        ],
                      ),
                      if (!wide) ...[
                        const SizedBox(height: 22),
                        Text(
                          count == 0
                              ? 'Ready when your first delivery arrives.'
                              : '$healthy of $count items above alert level · '
                                    '$attentionCount need attention',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFCCE1E2),
                          ),
                        ),
                      ],
                    ],
                  );
                  if (!wide) return text;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 7, child: text),
                      const SizedBox(width: 30),
                      Expanded(
                        flex: 3,
                        child: Semantics(
                          label:
                              'Stock health: $healthy of $count active items above their alert level, $attentionCount needing attention',
                          child: Column(
                            children: [
                              SizedBox(
                                width: 152,
                                height: 152,
                                child: CustomPaint(
                                  painter: _HealthRingPainter(
                                    count == 0 ? 0 : healthy / count,
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '$healthy',
                                          style: theme.textTheme.displaySmall
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        Text(
                                          'of $count items',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFFCCE1E2),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Above alert level',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$attentionCount need attention',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFFCCE1E2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentTile extends StatelessWidget {
  const _DepartmentTile({
    required this.department,
    required this.units,
    required this.used,
    required this.productCount,
    required this.alerts,
    required this.onTap,
  });

  final HotelDepartment department;
  final int units;
  final int used;
  final int productCount;
  final int alerts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      onTap: onTap,
      semanticLabel:
          '${department.label}, $units units on hand, $used used today, $alerts stock alerts. Open department.',
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _departmentIcon(department),
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.north_east_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(department.label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Text(
            '${AppFormatters.quantity(units)} on hand',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '$productCount items · $used used today',
            style: theme.textTheme.bodySmall,
          ),
          if (alerts > 0) ...[
            const SizedBox(height: 10),
            Text(
              '$alerts ${alerts == 1 ? 'item needs' : 'items need'} attention',
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.semanticColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    return Material(
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardHeading extends StatelessWidget {
  const _DashboardHeading({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final block = Semantics(
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 5),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        );
        final action = actionLabel == null
            ? null
            : TextButton(onPressed: onAction, child: Text(actionLabel!));
        if (constraints.maxWidth < 460 || _textScale(context) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [block, ?action],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: block),
            if (action != null) ...[const SizedBox(width: 10), action],
          ],
        );
      },
    );
  }
}

class _ResponsiveTiles extends StatelessWidget {
  const _ResponsiveTiles({
    required this.children,
    required this.minimumWidth,
    required this.maximumColumns,
  });

  final List<Widget> children;
  final double minimumWidth;
  final int maximumColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final scale = math.max(1.0, _textScale(context));
        final columns =
            ((constraints.maxWidth + gap) / (minimumWidth * scale + gap))
                .floor()
                .clamp(1, maximumColumns);
        final rows = (children.length / columns).ceil();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List<Widget>.generate(rows, (row) {
            final rowItems = List<Widget>.generate(columns, (column) {
              final index = row * columns + column;
              return Expanded(
                child: index < children.length
                    ? children[index]
                    : const SizedBox.shrink(),
              );
            });
            return Padding(
              padding: EdgeInsets.only(bottom: row == rows - 1 ? 0 : gap),
              child: columns == 1
                  ? children[row]
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var index = 0;
                            index < rowItems.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(width: gap),
                            rowItems[index],
                          ],
                        ],
                      ),
                    ),
            );
          }),
        );
      },
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle, style: theme.textTheme.bodyMedium),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _DayUsage {
  const _DayUsage(this.day, this.units, this.cost);
  final DateTime day;
  final int units;
  final int cost;
}

class _CoastalPainter extends CustomPainter {
  const _CoastalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..color = const Color(0xFFB5E8DC).withValues(alpha: .05);
    canvas.drawCircle(Offset(size.width * .96, size.height * .15), 175, glow);
    canvas.drawCircle(
      Offset(size.width * .91, size.height * .87),
      110,
      Paint()..color = const Color(0xFFF4CB85).withValues(alpha: .04),
    );
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .065)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var index = 0; index < 7; index++) {
      final offset = index * 17.0;
      final path = Path()
        ..moveTo(size.width * .54 + offset, size.height + 16)
        ..cubicTo(
          size.width * .50 + offset,
          size.height * .5,
          size.width + offset,
          size.height * .7,
          size.width + 20,
          -40 + offset,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CoastalPainter oldDelegate) => false;
}

class _HealthRingPainter extends CustomPainter {
  const _HealthRingPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(7);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .12);
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    if (fraction > 0) {
      paint.color = const Color(0xFFB5E8DC);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HealthRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

class _ChartGridPainter extends CustomPainter {
  const _ChartGridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .45)
      ..strokeWidth = .7;
    for (var index = 1; index <= 3; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

double _textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14;

Duration _motionDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 220);

IconData _departmentIcon(HotelDepartment department) => switch (department) {
  HotelDepartment.kitchen => Icons.restaurant_outlined,
  HotelDepartment.housekeeping => Icons.cleaning_services_outlined,
  HotelDepartment.laundry => Icons.local_laundry_service_outlined,
  HotelDepartment.maintenance => Icons.handyman_outlined,
  HotelDepartment.reception => Icons.room_service_outlined,
  HotelDepartment.office => Icons.business_center_outlined,
  HotelDepartment.publicArea => Icons.park_outlined,
  HotelDepartment.restaurant => Icons.dining_outlined,
  HotelDepartment.pool => Icons.pool_outlined,
  HotelDepartment.security => Icons.shield_outlined,
};
