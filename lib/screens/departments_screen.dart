import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import 'screen_helpers.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({
    super.key,
    required this.controller,
    this.initialDepartment,
  });

  final InventoryController controller;
  final HotelDepartment? initialDepartment;

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  HotelDepartment _selectedDepartment = HotelDepartment.kitchen;
  UsagePeriod _period = UsagePeriod.today;

  InventoryController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _selectedDepartment = widget.initialDepartment ?? HotelDepartment.kitchen;
  }

  @override
  void didUpdateWidget(covariant DepartmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDepartment != null &&
        widget.initialDepartment != oldWidget.initialDepartment) {
      _selectedDepartment = widget.initialDepartment!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = _selectedDepartment;
        final now = DateTime.now();
        final products = controller.activeProducts
            .where((product) => product.department == selected)
            .toList();
        final issues = controller
            .issuesForDepartment(selected)
            .where((issue) => _period.contains(issue.issuedAt, reference: now))
            .toList();
        final summaries = summarizeUsage(issues);
        final stockUnits = products.fold<int>(0, (sum, p) => sum + p.quantity);
        final stockValue = products.fold<int>(
          0,
          (sum, p) => sum + p.inventoryValueMinor,
        );
        final usedUnits = issues.fold<int>(0, (sum, i) => sum + i.quantity);
        final usedValue = issues.fold<int>(0, (sum, i) => sum + i.valueMinor);
        final horizontal = context.pagePadding.horizontal / 2;
        return SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: context.pagePadding.copyWith(bottom: 16),
                sliver: const SliverToBoxAdapter(
                  child: PageHeader(
                    eyebrow: 'Stock & consumption',
                    title: 'Departments',
                    subtitle:
                        'Stock belongs to its assigned department. Record what Kitchen or another team uses to reduce its stock and keep a dated history.',
                  ),
                ),
              ),
              _section(
                horizontal,
                Column(
                  children: [
                    DropdownButtonFormField<HotelDepartment>(
                      key: ValueKey(selected),
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Manage department',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                      items: HotelDepartment.values
                          .map(
                            (department) => DropdownMenuItem(
                              value: department,
                              child: Text(department.label),
                            ),
                          )
                          .toList(),
                      onChanged: (department) {
                        if (department != null) {
                          setState(() => _selectedDepartment = department);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: const Text('All departments overview'),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(top: 8),
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final largeText =
                                MediaQuery.textScalerOf(context).scale(14) > 17;
                            final columns =
                                largeText || constraints.maxWidth < 560
                                ? 1
                                : (constraints.maxWidth / 260).floor();
                            final cardWidth =
                                (constraints.maxWidth - (columns - 1) * 12) /
                                columns;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: List.generate(
                                HotelDepartment.values.length,
                                (index) {
                                  final department =
                                      HotelDepartment.values[index];
                                  final assigned = controller.activeProducts
                                      .where(
                                        (product) =>
                                            product.department == department,
                                      );
                                  final units = assigned.fold<int>(
                                    0,
                                    (sum, p) => sum + p.quantity,
                                  );
                                  final value = assigned.fold<int>(
                                    0,
                                    (sum, p) => sum + p.inventoryValueMinor,
                                  );
                                  final todayUsed = controller
                                      .issuesForDepartment(department)
                                      .where(
                                        (issue) => UsagePeriod.today.contains(
                                          issue.issuedAt,
                                          reference: now,
                                        ),
                                      )
                                      .fold<int>(
                                        0,
                                        (sum, issue) => sum + issue.quantity,
                                      );
                                  final selectedCard = selected == department;
                                  return SizedBox(
                                    width: cardWidth,
                                    child: SectionCard(
                                      onTap: () => setState(
                                        () => _selectedDepartment = department,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      semanticLabel:
                                          '${department.label}, $units stock units, $todayUsed units used today',
                                      backgroundColor: selectedCard
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer
                                          : null,
                                      borderColor: selectedCard
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : null,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                departmentIcon(department),
                                                size: 21,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  department.label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleSmall,
                                                ),
                                              ),
                                              if (selectedCard)
                                                const Icon(
                                                  Icons.check_circle_outline,
                                                  size: 17,
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 9),
                                          Text(
                                            '$units on hand · ${assigned.length} products',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            formatMoney(
                                              controller,
                                              value,
                                              compact: true,
                                            ),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '$todayUsed units used today',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                top: 0,
              ),
              _section(
                horizontal,
                _DepartmentHero(
                  department: selected,
                  productCount: products.length,
                  onRecordUsage: products.any((p) => p.quantity > 0)
                      ? () => _showUsageSheet(selected)
                      : null,
                ),
              ),
              _section(
                horizontal,
                UsageMetrics(
                  children: [
                    MetricCard(
                      label: 'Stock units (aggregate)',
                      value: AppFormatters.quantity(stockUnits),
                      icon: Icons.inventory_2_outlined,
                      helperText: '${products.length} assigned products',
                    ),
                    MetricCard(
                      label: 'Stock cost value',
                      value: formatMoney(controller, stockValue, compact: true),
                      icon: Icons.warehouse_outlined,
                    ),
                  ],
                ),
                top: 0,
              ),
              if (products.isEmpty)
                _section(
                  horizontal,
                  EmptyState(
                    compact: true,
                    icon: departmentIcon(selected),
                    title: 'No stock assigned to ${selected.label}',
                    message:
                        'Add a product in Inventory and choose ${selected.label} as its department.',
                  ),
                  top: 0,
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  sliver: SliverList.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return SectionCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ProductAvatar(product: product, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${product.sku} · ${product.category}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      _PreviewValue(
                                        label: 'On hand',
                                        value: '${product.quantity} units',
                                      ),
                                      _PreviewValue(
                                        label: 'Stock cost value',
                                        value: formatMoney(
                                          controller,
                                          product.inventoryValueMinor,
                                          compact: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      minHeight: 5,
                                      value:
                                          (product.quantity /
                                                  (product.lowStockThreshold > 0
                                                      ? product.lowStockThreshold *
                                                            2
                                                      : (product.quantity > 0
                                                            ? product.quantity
                                                            : 1)))
                                              .clamp(0.0, 1.0),
                                      color: product.isOutOfStock
                                          ? Theme.of(context).colorScheme.error
                                          : product.isLowStock
                                          ? context.semanticColors.warning
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: .1),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Stock entered ${AppFormatters.date(product.receivedAt.toLocal())}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      productStatusPill(context, product),
                                      if (product.quantity > 0)
                                        TextButton.icon(
                                          onPressed: () => _showUsageSheet(
                                            selected,
                                            productId: product.id,
                                          ),
                                          icon: const Icon(
                                            Icons.remove_circle_outline_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Use stock'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              _section(
                horizontal,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_graph_rounded,
                          color: context.semanticColors.warning,
                        ),
                        Text(
                          '${selected.label} consumption',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Quantities and costs are based on the date the items were used.',
                    ),
                    const SizedBox(height: 12),
                    UsagePeriodSelector(
                      selected: _period,
                      onSelected: (period) => setState(() => _period = period),
                    ),
                  ],
                ),
              ),
              _section(
                horizontal,
                UsageMetrics(
                  children: [
                    MetricCard(
                      label: 'Units used (aggregate)',
                      value: AppFormatters.quantity(usedUnits),
                      icon: Icons.restaurant_outlined,
                      helperText: _period.label,
                    ),
                    MetricCard(
                      label: 'Usage cost',
                      value: formatMoney(controller, usedValue, compact: true),
                      icon: Icons.payments_outlined,
                      helperText: '${issues.length} usage records',
                    ),
                  ],
                ),
                top: 0,
              ),
              if (issues.isEmpty)
                _section(
                  horizontal,
                  EmptyState(
                    compact: true,
                    icon: Icons.analytics_outlined,
                    title: 'No usage in this period',
                    message:
                        'Record what ${selected.label} uses, or choose All time to see older usage.',
                  ),
                  top: 0,
                )
              else ...[
                _section(
                  horizontal,
                  Text(
                    'Used by product',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  top: 8,
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  sliver: SliverList.separated(
                    itemCount: summaries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => UsageProductTile(
                      summary: summaries[index],
                      controller: controller,
                    ),
                  ),
                ),
                _section(
                  horizontal,
                  Text(
                    'Dated usage history',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  sliver: SliverList.separated(
                    itemCount: issues.length,
                    separatorBuilder: (_, _) => const Divider(height: 20),
                    itemBuilder: (context, index) => UsageHistoryTile(
                      issue: issues[index],
                      controller: controller,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        );
      },
    );
  }

  Widget _section(double horizontal, Widget child, {double top = 24}) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 16),
        sliver: SliverToBoxAdapter(child: child),
      );

  Future<void> _showUsageSheet(
    HotelDepartment department, {
    String? productId,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _UsageStockSheet(
      controller: controller,
      department: department,
      productId: productId,
    ),
  );
}

class _UsageStockSheet extends StatefulWidget {
  const _UsageStockSheet({
    required this.controller,
    required this.department,
    this.productId,
  });

  final InventoryController controller;
  final HotelDepartment department;
  final String? productId;

  @override
  State<_UsageStockSheet> createState() => _UsageStockSheetState();
}

class _DepartmentHero extends StatelessWidget {
  const _DepartmentHero({
    required this.department,
    required this.productCount,
    required this.onRecordUsage,
  });
  final HotelDepartment department;
  final int productCount;
  final VoidCallback? onRecordUsage;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF142B35), Color(0xFF0E766E)],
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                departmentIcon(department),
                color: const Color(0xFFBDEDD9),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TEAM WORKSPACE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFBDEDD9),
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    department.label,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '$productCount assigned products. A clear view of what is in stock and what your team uses.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFE2F1ED)),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFBDEDD9),
            foregroundColor: const Color(0xFF142B35),
            disabledBackgroundColor: Colors.white12,
            disabledForegroundColor: Colors.white70,
          ),
          onPressed: onRecordUsage,
          icon: const Icon(Icons.remove_circle_outline_rounded),
          label: const Text('Record usage'),
        ),
      ],
    ),
  );
}

class _UsageStockSheetState extends State<_UsageStockSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  String? _productId;
  DateTime _usedAt = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _productId = widget.productId;
  }

  Product? get _currentProduct =>
      _productId == null ? null : widget.controller.productById(_productId!);

  int get _quantity => int.tryParse(_quantityController.text) ?? 0;

  void _changeQuantity(int difference) {
    final max = _currentProduct?.quantity;
    if (_saving || max == null || max < 1) return;
    final next = (_quantity + difference).clamp(1, max);
    _quantityController.value = TextEditingValue(
      text: '$next',
      selection: TextSelection.collapsed(offset: '$next'.length),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _usedAt,
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
      helpText: 'Date these items were used',
    );
    if (chosen != null && mounted) setState(() => _usedAt = chosen);
  }

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final product = _currentProduct;
    if (product == null ||
        product.isArchived ||
        product.department != widget.department) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This product is no longer available in this department.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.issueStock(
        product.id,
        widget.department,
        int.parse(_quantityController.text),
        usedAt: _usedAt,
        note: _noteController.text.trim(),
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${widget.department.label} usage recorded. Stock reduced.',
            ),
          ),
        );
      }
    } on InventoryException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final products = widget.controller.activeProducts
          .where(
            (product) =>
                product.department == widget.department && product.quantity > 0,
          )
          .toList();
      final selectedAvailable = products.any((p) => p.id == _productId);
      final submitted = widget.controller.isDailyReportSubmitted(_usedAt);
      final current = _currentProduct;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  eyebrow: widget.department.label,
                  title: 'Record usage',
                  subtitle:
                      'Record what ${widget.department.label} used. Saving reduces this department’s on-hand stock, not a transfer to another store.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedAvailable ? _productId : null),
                  initialValue: selectedAvailable ? _productId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Department product',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  items: products
                      .map(
                        (product) => DropdownMenuItem(
                          value: product.id,
                          child: Text(
                            '${product.name} (${product.quantity} available)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _productId = value),
                  validator: (value) => value == null || !selectedAvailable
                      ? 'Choose an available product'
                      : null,
                ),
                if (current != null && selectedAvailable) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${current.quantity} available · Stock entered ${AppFormatters.date(current.receivedAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Usage date: ${AppFormatters.date(_usedAt)}'),
                ),
                if (submitted) ...[
                  const SizedBox(height: 8),
                  Text(
                    'This day’s report is already submitted. Usage is locked for this date; choose an open day.',
                    style: TextStyle(color: context.semanticColors.warning),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _quantityController,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Quantity used',
                    prefixIcon: Icon(Icons.numbers),
                  ),
                  validator: (value) {
                    final quantity = int.tryParse(value ?? '');
                    if (quantity == null || quantity <= 0) {
                      return 'Enter a quantity greater than zero';
                    }
                    final product = _currentProduct;
                    if (product == null ||
                        product.isArchived ||
                        product.department != widget.department) {
                      return 'Choose an available department product';
                    }
                    if (quantity > product.quantity) {
                      return 'Only ${product.quantity} available';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: !_saving && _quantity > 1 && current != null
                          ? () => _changeQuantity(-1)
                          : null,
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      label: const Text('1'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          !_saving &&
                              current != null &&
                              _quantity < current.quantity
                          ? () => _changeQuantity(1)
                          : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('1'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          !_saving &&
                              current != null &&
                              _quantity < current.quantity
                          ? () => _changeQuantity(5)
                          : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('5'),
                    ),
                  ],
                ),
                if (current != null && selectedAvailable) ...[
                  const SizedBox(height: 16),
                  _UsagePreview(
                    product: current,
                    quantity: _quantity,
                    controller: widget.controller,
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _noteController,
                  enabled: !_saving,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Purpose or note (optional)',
                    hintText: 'For example: Lunch preparation',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving || products.isEmpty || submitted
                      ? null
                      : _submit,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_outlined),
                  label: Text(
                    products.isEmpty
                        ? 'No available stock in this department'
                        : _saving
                        ? 'Recording usage…'
                        : 'Save usage & reduce stock',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

enum UsagePeriod {
  today('Today', 1),
  sevenDays('7 days', 7),
  thirtyDays('30 days', 30),
  all('All time', null);

  const UsagePeriod(this.label, this.days);
  final String label;
  final int? days;

  bool contains(DateTime value, {required DateTime reference}) {
    final local = value.toLocal();
    final end = DateTime(reference.year, reference.month, reference.day + 1);
    if (!local.isBefore(end)) return false;
    final count = days;
    return count == null ||
        !local.isBefore(
          DateTime(reference.year, reference.month, reference.day - count + 1),
        );
  }
}

class _UsagePreview extends StatelessWidget {
  const _UsagePreview({
    required this.product,
    required this.quantity,
    required this.controller,
  });
  final Product product;
  final int quantity;
  final InventoryController controller;

  @override
  Widget build(BuildContext context) {
    final valid = quantity > 0 && quantity <= product.quantity;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      backgroundColor: valid
          ? scheme.primaryContainer.withValues(alpha: .5)
          : scheme.errorContainer.withValues(alpha: .5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LIVE STOCK PREVIEW',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: valid ? scheme.primary : scheme.error,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _PreviewValue(
                label: 'Before',
                value: '${product.quantity} units',
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: scheme.primary,
              ),
              _PreviewValue(
                label: 'After saving',
                value: valid
                    ? '${product.quantity - quantity} units'
                    : 'Check quantity',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Usage cost: ${formatMoney(controller, valid ? quantity * product.unitCostMinor : 0)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${formatMoney(controller, product.unitCostMinor)} per unit · Captured when you save',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PreviewValue extends StatelessWidget {
  const _PreviewValue({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 3),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class UsagePeriodSelector extends StatelessWidget {
  const UsagePeriodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final UsagePeriod? selected;
  final ValueChanged<UsagePeriod> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: UsagePeriod.values
        .map(
          (period) => ChoiceChip(
            label: Text(period.label),
            selected: selected == period,
            onSelected: (_) => onSelected(period),
          ),
        )
        .toList(),
  );
}

class UsageMetrics extends StatelessWidget {
  const UsageMetrics({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 460 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3
          ? children.length
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

class UsageProductSummary {
  UsageProductSummary(this.issue);
  final DepartmentIssue issue;
  int quantity = 0;
  int valueMinor = 0;
  int recordCount = 0;
}

List<UsageProductSummary> summarizeUsage(Iterable<DepartmentIssue> issues) {
  final grouped = <String, UsageProductSummary>{};
  for (final issue in issues) {
    final key = '${issue.department.name}:${issue.productId}';
    final summary = grouped.putIfAbsent(key, () => UsageProductSummary(issue));
    summary.quantity += issue.quantity;
    summary.valueMinor += issue.valueMinor;
    summary.recordCount++;
  }
  return grouped.values.toList()
    ..sort((a, b) => b.quantity.compareTo(a.quantity));
}

class UsageProductTile extends StatelessWidget {
  const UsageProductTile({
    super.key,
    required this.summary,
    required this.controller,
  });
  final UsageProductSummary summary;
  final InventoryController controller;

  @override
  Widget build(BuildContext context) => SectionCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary.issue.productName,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${summary.issue.department.label} · ${summary.issue.productSku}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            Text('${AppFormatters.quantity(summary.quantity)} units used'),
            Text('${formatMoney(controller, summary.valueMinor)} cost'),
          ],
        ),
      ],
    ),
  );
}

class UsageHistoryTile extends StatelessWidget {
  const UsageHistoryTile({
    super.key,
    required this.issue,
    required this.controller,
  });
  final DepartmentIssue issue;
  final InventoryController controller;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 3),
        child: Icon(Icons.restaurant_outlined, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              issue.productName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${issue.department.label} · Used ${AppFormatters.date(issue.issuedAt.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('${AppFormatters.quantity(issue.quantity)} units used'),
                Text('${formatMoney(controller, issue.valueMinor)} cost'),
              ],
            ),
            if (issue.note != null && issue.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(issue.note!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ],
  );
}

IconData departmentIcon(HotelDepartment department) => switch (department) {
  HotelDepartment.kitchen => Icons.restaurant,
  HotelDepartment.housekeeping => Icons.cleaning_services,
  HotelDepartment.laundry => Icons.local_laundry_service,
  HotelDepartment.maintenance => Icons.build,
  HotelDepartment.reception => Icons.desk,
  HotelDepartment.office => Icons.business_center,
  HotelDepartment.publicArea => Icons.weekend,
  HotelDepartment.restaurant => Icons.restaurant_menu,
  HotelDepartment.pool => Icons.pool,
  HotelDepartment.security => Icons.shield_outlined,
};
