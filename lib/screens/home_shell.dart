import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import 'inventory_screen.dart';
import 'dashboard_screen.dart';
import 'workspace_actions.dart';
import 'departments_screen.dart';
import 'product_form_screen.dart';
import 'reports_screen.dart';
import 'requisitions_screen.dart';
import 'sale_screen.dart';
import 'screen_helpers.dart';
import 'settings_screen.dart';
import 'stock_actions.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.controller,
    required this.authService,
    required this.onSignOut,
  });

  final InventoryController controller;
  final AuthService authService;
  final VoidCallback onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  HotelDepartment? _shortcutDepartment;
  int _departmentVisit = 0;
  String _actorName = 'Hotel administrator';
  late final AnimationController _pageAnimation;

  @override
  void initState() {
    super.initState();
    _pageAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    _loadActorName();
  }

  Future<void> _loadActorName() async {
    final name = await widget.authService.accountName;
    if (!mounted || name == null || name.trim().isEmpty) return;
    setState(() => _actorName = name.trim());
    _controller.setCurrentActor(name);
  }

  @override
  void dispose() {
    _pageAnimation.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    if (index == _selectedIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageAnimation.value = 1;
    } else {
      _pageAnimation.forward(from: 0);
    }
  }

  void _openDepartment(HotelDepartment department) {
    setState(() {
      _shortcutDepartment = department;
      _departmentVisit++;
    });
    _selectPage(3);
  }

  Future<void> _showMore() async {
    final destination = await showWorkspaceMenu(context);
    if (destination != null && mounted) _selectPage(destination);
  }

  Future<void> _showQuickActions() async {
    final action = await showWorkspaceActions(context);
    if (!mounted || action == null) return;
    switch (action) {
      case WorkspaceAction.product:
        await _addProduct();
      case WorkspaceAction.receive:
        await _receiveDelivery();
      case WorkspaceAction.usage:
        _selectPage(6);
      case WorkspaceAction.sale:
        _openSale();
    }
  }

  Future<void> _receiveDelivery() async {
    if (_controller.activeProducts.isEmpty) {
      await _addProduct();
      return;
    }
    final product = await showReceiveProductPicker(
      context,
      controller: _controller,
    );
    if (mounted && product != null) {
      await showRestockSheet(
        context,
        controller: _controller,
        product: product,
      );
    }
  }

  Future<void> _refreshInventory() async {
    try {
      await _controller.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Latest inventory loaded.')),
        );
      }
    } on InventoryException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  InventoryController get _controller => widget.controller;

  void _openProduct(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductActionsSheet(
        controller: _controller,
        product: product,
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _addProduct() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProductFormScreen(controller: _controller),
      ),
    );
  }

  void _openSale([String? productId]) {
    _selectPage(2);
    if (productId == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NewSaleScreen(
          controller: _controller,
          initialProductId: productId,
          standalone: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardScreen(
        controller: _controller,
        onAddProduct: _addProduct,
        onOpenInventory: () => _selectPage(1),
        onOpenSale: () => _openSale(),
        onOpenProduct: _openProduct,
        onOpenDepartment: _openDepartment,
        onOpenReports: () => _selectPage(4),
        onReceiveDelivery: _receiveDelivery,
      ),
      InventoryScreen(
        controller: _controller,
        onAddProduct: _addProduct,
        onProductTap: _openProduct,
        onRestock: (product) => showRestockSheet(
          context,
          controller: _controller,
          product: product,
        ),
      ),
      NewSaleScreen(
        controller: _controller,
        onAddProduct: _addProduct,
        onLoadStarterInventory: AppConfig.allowDemoData
            ? _loadStarterInventory
            : null,
      ),
      DepartmentsScreen(
        key: ValueKey(_departmentVisit),
        controller: _controller,
        initialDepartment: _shortcutDepartment,
      ),
      ReportsScreen(controller: _controller),
      _ActivityPage(controller: _controller),
      RequisitionsScreen(controller: _controller, actorName: _actorName),
      SettingsScreen(controller: _controller),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final destinations = const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Sell',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: 'Departments',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Requisitions',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ];
        final wide = constraints.maxWidth >= AppBreakpoints.medium;
        final content = FadeTransition(
          opacity: _pageAnimation,
          child: IndexedStack(index: _selectedIndex, children: pages),
        );

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  scrollable: true,
                  onDestinationSelected: _selectPage,
                  extended: true,
                  trailing: SizedBox(
                    width: 248,
                    child: _ProfileButton(
                      authService: widget.authService,
                      onSignOut: widget.onSignOut,
                    ),
                  ),
                  leading: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 28),
                    child: const SizedBox(
                      width: 232,
                      child: _BrandMark(extended: true),
                    ),
                  ),
                  destinations: destinations
                      .map(
                        (destination) => NavigationRailDestination(
                          icon: destination.icon,
                          selectedIcon: destination.selectedIcon,
                          label: Text(destination.label),
                        ),
                      )
                      .toList(growable: false),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          drawer: _AppDrawer(
            authService: widget.authService,
            onSignOut: widget.onSignOut,
            selectedIndex: _selectedIndex,
            onSelected: (index) {
              Navigator.of(context).pop();
              _selectPage(index);
            },
            destinations: destinations,
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: .45),
                ),
              ),
            ),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: NavigationBar(
                height: 78,
                selectedIndex: switch (_selectedIndex) {
                  0 => 0,
                  1 => 1,
                  3 => 2,
                  4 => 3,
                  _ => 4,
                },
                onDestinationSelected: (index) {
                  if (index == 4) {
                    _showMore();
                  } else {
                    _selectPage([0, 1, 3, 4][index]);
                  }
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.space_dashboard_outlined),
                    selectedIcon: Icon(Icons.space_dashboard_rounded),
                    label: 'Overview',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2_rounded),
                    label: 'Inventory',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.account_tree_outlined),
                    selectedIcon: Icon(Icons.account_tree_rounded),
                    label: 'Teams',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.insights_outlined),
                    selectedIcon: Icon(Icons.insights_rounded),
                    label: 'Reports',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.more_horiz_rounded),
                    label: 'More',
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: [0, 1, 3].contains(_selectedIndex)
              ? FloatingActionButton.small(
                  onPressed: _showQuickActions,
                  tooltip: 'Open quick actions',
                  child: const Icon(Icons.add_rounded),
                )
              : null,
          body: Builder(
            builder: (scaffoldContext) => Column(
              children: [
                SafeArea(
                  top: true,
                  bottom: false,
                  child: _MobileTopBar(
                    onMenuPressed: () =>
                        Scaffold.of(scaffoldContext).openDrawer(),
                    onQuickActions: _showQuickActions,
                    onRefresh: widget.authService.isRemote
                        ? _refreshInventory
                        : null,
                  ),
                ),
                Expanded(child: content),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadStarterInventory() async {
    try {
      await _controller.seedDemoData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hotel starter inventory is ready to sell.'),
        ),
      );
    } on InventoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = Container(
      width: 42,
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Image.asset('assets/sau_inn_logo.png', fit: BoxFit.contain),
    );
    if (!extended) return mark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DreamStore',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'SAU INN · STOCK STUDIO',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: .7,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.onMenuPressed,
    required this.onQuickActions,
    this.onRefresh,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback onQuickActions;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 20, 4),
        child: Row(
          children: [
            IconButton(
              onPressed: onMenuPressed,
              tooltip: 'Open navigation menu',
              icon: const Icon(Icons.menu_rounded),
            ),
            const Expanded(child: _BrandMark(extended: true)),
            const SizedBox(width: 8),
            if (onRefresh != null)
              IconButton(
                onPressed: onRefresh,
                tooltip: 'Refresh live inventory',
                icon: const Icon(Icons.sync_rounded),
              ),
            IconButton.filledTonal(
              onPressed: onQuickActions,
              tooltip: 'Open quick actions',
              icon: const Icon(Icons.bolt_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.authService,
    required this.onSignOut,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final AuthService authService;
  final VoidCallback onSignOut;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandMark(extended: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'The Dream Of Sau Inn Beach Hotel',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _ProfileButton(
              authService: authService,
              onSignOut: onSignOut,
              expanded: true,
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < destinations.length; index++)
              ListTile(
                selected: index == selectedIndex,
                selectedTileColor: theme.colorScheme.primaryContainer,
                leading: index == selectedIndex
                    ? destinations[index].selectedIcon
                    : destinations[index].icon,
                title: Text(destinations[index].label),
                onTap: () => onSelected(index),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Text('Hotel stock desk', style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.authService,
    required this.onSignOut,
    this.expanded = false,
  });

  final AuthService authService;
  final VoidCallback onSignOut;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: authService.accountName,
      builder: (context, snapshot) {
        final name = snapshot.data?.trim().isNotEmpty == true
            ? snapshot.data!
            : 'Hotel administrator';
        final avatar = CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
          child: Text(name.substring(0, 1).toUpperCase()),
        );
        final content = ListTile(
          dense: !expanded,
          leading: avatar,
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: expanded ? const Text('Administrator profile') : null,
          trailing: const Icon(Icons.more_horiz),
          onTap: () => _openProfile(context, name),
        );
        return expanded ? content : Tooltip(message: name, child: content);
      },
    );
  }

  Future<void> _openProfile(BuildContext context, String name) async {
    final email = await authService.accountEmail;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your profile', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(name),
              subtitle: Text(email ?? 'Local hotel account'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                onSignOut();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
            const SizedBox(height: 8),
            if (!authService.isRemote)
              TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      icon: Icon(
                        Icons.warning_amber_rounded,
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                      title: const Text('Remove account from this device?'),
                      content: const Text(
                        'This removes the saved login account from this device. '
                        'Hotel inventory and reports will remain unchanged.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Remove account'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await authService.resetAllAccounts();
                  if (context.mounted) Navigator.pop(context);
                  onSignOut();
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove account from this device'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({required this.controller});

  final InventoryController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
              sliver: SliverToBoxAdapter(
                child: PageHeader(
                  eyebrow: 'Audit trail',
                  title: 'Activity',
                  subtitle:
                      'Every sale, delivery, and correction in one timeline.',
                ),
              ),
            ),
            if (controller.recentMovements.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.history,
                  title: 'No activity yet',
                  message:
                      'Stock movements will appear here as you receive products and record sales.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.separated(
                  itemCount: controller.recentMovements.length,
                  separatorBuilder: (_, _) => const Divider(height: 20),
                  itemBuilder: (context, index) => MovementListTile(
                    movement: controller.recentMovements[index],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductActionsSheet extends StatelessWidget {
  const _ProductActionsSheet({
    required this.controller,
    required this.product,
    required this.onChanged,
  });

  final InventoryController controller;
  final Product product;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final deliveries =
        controller.movements
            .where(
              (movement) =>
                  movement.productId == product.id &&
                  (movement.type == StockMovementType.opening ||
                      movement.type == StockMovementType.restock),
            )
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: product.name,
              subtitle:
                  '${product.sku}  |  ${product.quantity} ${product.unit} available\n'
                  '${product.department.label}',
            ),
            const SizedBox(height: 16),
            Text(
              'Stock entered: ${AppFormatters.date(product.receivedAt.toLocal(), includeWeekday: true)}',
            ),
            if (deliveries.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Latest arrival: ${AppFormatters.date(deliveries.first.occurredAt.toLocal())}',
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _DeliveryHistorySheet(
                  controller: controller,
                  product: product,
                  deliveries: deliveries,
                ),
              ),
              icon: const Icon(Icons.event_note_outlined),
              label: Text('Delivery history (${deliveries.length})'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: product.isArchived
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await showRestockSheet(
                        context,
                        controller: controller,
                        product: product,
                      );
                      onChanged();
                    },
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Receive stock'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: product.isArchived
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await showAdjustStockSheet(
                        context,
                        controller: controller,
                        product: product,
                      );
                      onChanged();
                    },
              icon: const Icon(Icons.tune),
              label: const Text('Adjust stock count'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProductFormScreen(
                      controller: controller,
                      product: product,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit product details'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryHistorySheet extends StatelessWidget {
  const _DeliveryHistorySheet({
    required this.controller,
    required this.product,
    required this.deliveries,
  });

  final InventoryController controller;
  final Product product;
  final List<StockMovement> deliveries;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Delivery history',
              subtitle:
                  '${product.name}\nSupplier, invoice, arrival, expiry, quantity, and cost for each entry.',
            ),
            const SizedBox(height: 16),
            Expanded(
              child: deliveries.isEmpty
                  ? const Center(
                      child: Text('No stock deliveries recorded yet.'),
                    )
                  : ListView.separated(
                      itemCount: deliveries.length,
                      separatorBuilder: (_, _) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final delivery = deliveries[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MovementListTile(movement: delivery),
                            Text(
                              'Unit cost: ${formatMoney(controller, delivery.unitCostMinor)}',
                            ),
                            if (delivery.supplierName != null)
                              Text('Supplier: ${delivery.supplierName}'),
                            if (delivery.invoiceNumber != null)
                              Text('Invoice: ${delivery.invoiceNumber}'),
                            if (delivery.expiryDate != null)
                              Text(
                                'Expiry date: ${AppFormatters.date(delivery.expiryDate!.toLocal())}',
                              ),
                            if (delivery.actorName != null)
                              Text('Recorded by: ${delivery.actorName}'),
                            if (delivery.note?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 4),
                              Text(delivery.note!),
                            ],
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
