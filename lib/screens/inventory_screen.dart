import 'package:flutter/material.dart';

import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.controller,
    required this.onAddProduct,
    required this.onProductTap,
    required this.onRestock,
  });

  final InventoryController controller;
  final VoidCallback onAddProduct;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<Product> onRestock;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  _InventoryFilter _filter = _InventoryFilter.all;
  _InventorySort _sort = _InventorySort.name;
  HotelDepartment? _department;
  String _query = '';
  bool _gridView = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _filter = _InventoryFilter.all;
      _department = null;
    });
  }

  List<Product> _visibleProducts(Iterable<Product> source) {
    final normalizedQuery = _query.trim().toLowerCase();
    final products = source.where((product) {
      final matchesFilter = switch (_filter) {
        _InventoryFilter.all => !product.isArchived,
        _InventoryFilter.inStock => !product.isArchived && product.isInStock,
        _InventoryFilter.lowStock => !product.isArchived && product.isLowStock,
        _InventoryFilter.outOfStock =>
          !product.isArchived && product.isOutOfStock,
        _InventoryFilter.archived => product.isArchived,
      };
      if (!matchesFilter) return false;
      if (_department != null && product.department != _department) {
        return false;
      }
      if (normalizedQuery.isEmpty) return true;

      return product.name.toLowerCase().contains(normalizedQuery) ||
          product.sku.toLowerCase().contains(normalizedQuery) ||
          product.category.toLowerCase().contains(normalizedQuery) ||
          product.department.label.toLowerCase().contains(normalizedQuery) ||
          product.description.toLowerCase().contains(normalizedQuery);
    }).toList();

    int compareByName(Product first, Product second) =>
        first.name.toLowerCase().compareTo(second.name.toLowerCase());

    products.sort((first, second) {
      final comparison = switch (_sort) {
        _InventorySort.name => compareByName(first, second),
        _InventorySort.quantity => second.quantity.compareTo(first.quantity),
        _InventorySort.value => second.retailValueMinor.compareTo(
          first.retailValueMinor,
        ),
        _InventorySort.recent => second.updatedAt.compareTo(first.updatedAt),
      };
      return comparison == 0 ? compareByName(first, second) : comparison;
    });
    return products;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (widget.controller.isLoading && !widget.controller.hasLoaded) {
          return const _InventoryLoadingState();
        }

        final allProducts = widget.controller.products.toList(growable: false);
        final visibleProducts = _visibleProducts(allProducts);
        final counts = _InventoryCounts.from(allProducts);
        final departmentCounts = _InventoryCounts.from(
          allProducts.where(
            (product) =>
                _department == null || product.department == _department,
          ),
        );
        final groupedProducts = <HotelDepartment, List<Product>>{
          for (final department in HotelDepartment.values)
            department: visibleProducts
                .where((product) => product.department == department)
                .toList(growable: false),
        };
        final settings = widget.controller.settings;

        return SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = switch (constraints.maxWidth) {
                >= AppBreakpoints.expanded => AppSpacing.xxl,
                >= AppBreakpoints.compact => AppSpacing.xl,
                _ => AppSpacing.md,
              };
              final contentWidth = constraints.maxWidth - horizontalPadding * 2;
              final gridColumns =
                  _gridView &&
                      contentWidth >= 680 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3
                  ? (contentWidth / 330).floor().clamp(2, 4)
                  : 1;

              return CustomScrollView(
                key: const PageStorageKey<String>('inventory-scroll'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      AppSpacing.md,
                    ),
                    sliver: SliverList.list(
                      children: [
                        PageHeader(
                          eyebrow: 'Stock control',
                          title: 'Inventory',
                          subtitle:
                              '${AppFormatters.quantity(counts.active)} active '
                              '${counts.active == 1 ? 'product' : 'products'} '
                              'organized by department. Track arrival dates '
                              'and stock available for each team.',
                          action: FilledButton.icon(
                            onPressed: widget.onAddProduct,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add product'),
                          ),
                        ),
                        if (widget.controller.isSaving) ...[
                          const SizedBox(height: AppSpacing.md),
                          const ClipRRect(
                            borderRadius: BorderRadius.all(
                              Radius.circular(AppRadii.small),
                            ),
                            child: LinearProgressIndicator(minHeight: 3),
                          ),
                        ],
                        if (widget.controller.error case final error?) ...[
                          const SizedBox(height: AppSpacing.md),
                          _ErrorBanner(
                            message: error,
                            onDismiss: widget.controller.clearError,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        _InventoryToolbar(
                          searchController: _searchController,
                          query: _query,
                          selectedSort: _sort,
                          gridView: _gridView,
                          onViewChanged: (value) =>
                              setState(() => _gridView = value),
                          onQueryChanged: (value) {
                            setState(() => _query = value);
                          },
                          onSortChanged: (value) {
                            setState(() => _sort = value);
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _DepartmentFilterBar(
                          selected: _department,
                          products: allProducts,
                          archived: _filter == _InventoryFilter.archived,
                          onSelected: (value) {
                            setState(() => _department = value);
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _FilterBar(
                          selected: _filter,
                          counts: departmentCounts,
                          onSelected: (value) {
                            setState(() => _filter = value);
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _ResultsSummary(
                          visibleCount: visibleProducts.length,
                          totalCount: departmentCounts.forFilter(_filter),
                          sort: _sort,
                        ),
                      ],
                    ),
                  ),
                  if (visibleProducts.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          AppSpacing.xxl,
                        ),
                        child: _buildEmptyState(
                          allProducts: allProducts,
                          counts: counts,
                        ),
                      ),
                    )
                  else
                    for (final entry in groupedProducts.entries)
                      if (entry.value.isNotEmpty) ...[
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            AppSpacing.xs,
                            horizontalPadding,
                            AppSpacing.md,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: _DepartmentHeading(
                              department: entry.key,
                              productCount: entry.value.length,
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            0,
                            horizontalPadding,
                            AppSpacing.lg,
                          ),
                          sliver: SliverList.separated(
                            itemCount: (entry.value.length / gridColumns)
                                .ceil(),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, row) => Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (
                                  var column = 0;
                                  column < gridColumns;
                                  column++
                                ) ...[
                                  if (column > 0)
                                    const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child:
                                        row * gridColumns + column <
                                            entry.value.length
                                        ? _ProductCard(
                                            product:
                                                entry.value[row * gridColumns +
                                                    column],
                                            settings: settings,
                                            compact: !_gridView,
                                            onTap: widget.onProductTap,
                                            onRestock: widget.onRestock,
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required List<Product> allProducts,
    required _InventoryCounts counts,
  }) {
    if (allProducts.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Build your inventory',
        message:
            'Add your first product to track stock, pricing, sales, and every '
            'quantity change in one place.',
        actionLabel: 'Add first product',
        onAction: widget.onAddProduct,
      );
    }

    if (_query.trim().isNotEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching products',
        message:
            'Nothing in ${_filter.label.toLowerCase()} matches “${_query.trim()}”. '
            'Try a product name, SKU, category, or department.',
        action: OutlinedButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.filter_alt_off_outlined),
          label: const Text('Clear search and filters'),
        ),
      );
    }

    if (_department != null) {
      return EmptyState(
        icon: _departmentIcon(_department!),
        title: 'No products in ${_department!.label}',
        message:
            'No products in this department match the current stock filter. '
            'Assign a department when adding or editing a product.',
        action: OutlinedButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.filter_alt_off_outlined),
          label: const Text('Show all departments'),
        ),
      );
    }

    if (_filter == _InventoryFilter.all && counts.archived > 0) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No active products',
        message:
            'Your products are archived. You can still open them to review '
            'their information.',
        actionLabel: 'View archived',
        actionIcon: Icons.archive_outlined,
        onAction: () => setState(() => _filter = _InventoryFilter.archived),
      );
    }

    return EmptyState(
      icon: _filter.emptyIcon,
      title: 'No ${_filter.label.toLowerCase()} products',
      message: _filter.emptyMessage,
      action: OutlinedButton.icon(
        onPressed: _clearFilters,
        icon: const Icon(Icons.filter_alt_off_outlined),
        label: const Text('Show all products'),
      ),
    );
  }
}

enum _InventoryFilter { all, inStock, lowStock, outOfStock, archived }

extension on _InventoryFilter {
  String get label => switch (this) {
    _InventoryFilter.all => 'All',
    _InventoryFilter.inStock => 'In stock',
    _InventoryFilter.lowStock => 'Low stock',
    _InventoryFilter.outOfStock => 'Out of stock',
    _InventoryFilter.archived => 'Archived',
  };

  IconData get icon => switch (this) {
    _InventoryFilter.all => Icons.apps_rounded,
    _InventoryFilter.inStock => Icons.check_circle_outline_rounded,
    _InventoryFilter.lowStock => Icons.warning_amber_rounded,
    _InventoryFilter.outOfStock => Icons.remove_shopping_cart_outlined,
    _InventoryFilter.archived => Icons.archive_outlined,
  };

  IconData get emptyIcon => switch (this) {
    _InventoryFilter.all => Icons.inventory_2_outlined,
    _InventoryFilter.inStock => Icons.check_circle_outline_rounded,
    _InventoryFilter.lowStock => Icons.notifications_none_rounded,
    _InventoryFilter.outOfStock => Icons.inventory_outlined,
    _InventoryFilter.archived => Icons.archive_outlined,
  };

  String get emptyMessage => switch (this) {
    _InventoryFilter.all => 'Add a product to start tracking your stock.',
    _InventoryFilter.inStock =>
      'There are no products with available stock right now.',
    _InventoryFilter.lowStock =>
      'Everything is above its low-stock alert level. Nice work.',
    _InventoryFilter.outOfStock =>
      'No products are sold out. Your shelves are covered.',
    _InventoryFilter.archived =>
      'Archived products will appear here when you retire an item.',
  };
}

enum _InventorySort { name, quantity, value, recent }

extension on _InventorySort {
  String get label => switch (this) {
    _InventorySort.name => 'Name',
    _InventorySort.quantity => 'Quantity',
    _InventorySort.value => 'Stock value',
    _InventorySort.recent => 'Recently updated',
  };

  IconData get icon => switch (this) {
    _InventorySort.name => Icons.sort_by_alpha_rounded,
    _InventorySort.quantity => Icons.format_list_numbered_rounded,
    _InventorySort.value => Icons.payments_outlined,
    _InventorySort.recent => Icons.schedule_rounded,
  };
}

class _InventoryCounts {
  const _InventoryCounts({
    required this.active,
    required this.inStock,
    required this.lowStock,
    required this.outOfStock,
    required this.archived,
  });

  factory _InventoryCounts.from(Iterable<Product> products) {
    var active = 0;
    var inStock = 0;
    var lowStock = 0;
    var outOfStock = 0;
    var archived = 0;

    for (final product in products) {
      if (product.isArchived) {
        archived++;
        continue;
      }
      active++;
      if (product.isInStock) inStock++;
      if (product.isLowStock) lowStock++;
      if (product.isOutOfStock) outOfStock++;
    }

    return _InventoryCounts(
      active: active,
      inStock: inStock,
      lowStock: lowStock,
      outOfStock: outOfStock,
      archived: archived,
    );
  }

  final int active;
  final int inStock;
  final int lowStock;
  final int outOfStock;
  final int archived;

  int forFilter(_InventoryFilter filter) => switch (filter) {
    _InventoryFilter.all => active,
    _InventoryFilter.inStock => inStock,
    _InventoryFilter.lowStock => lowStock,
    _InventoryFilter.outOfStock => outOfStock,
    _InventoryFilter.archived => archived,
  };
}

class _InventoryToolbar extends StatelessWidget {
  const _InventoryToolbar({
    required this.searchController,
    required this.query,
    required this.selectedSort,
    required this.onQueryChanged,
    required this.onSortChanged,
    required this.gridView,
    required this.onViewChanged,
  });

  final TextEditingController searchController;
  final String query;
  final _InventorySort selectedSort;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_InventorySort> onSortChanged;
  final bool gridView;
  final ValueChanged<bool> onViewChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = AppSearchField(
          controller: searchController,
          hintText: 'Search products or departments',
          onChanged: onQueryChanged,
          onClear: query.isEmpty ? null : () => onQueryChanged(''),
        );
        final sort = _SortMenu(
          selected: selectedSort,
          onSelected: onSortChanged,
        );
        final view = SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: true,
              icon: Icon(Icons.grid_view_rounded),
              tooltip: 'Card view',
            ),
            ButtonSegment(
              value: false,
              icon: Icon(Icons.view_list_rounded),
              tooltip: 'Compact list view',
            ),
          ],
          selected: {gridView},
          onSelectionChanged: (selection) => onViewChanged(selection.first),
        );

        if (constraints.maxWidth < 680 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [sort, view],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: AppSpacing.sm),
            sort,
            const SizedBox(width: AppSpacing.sm),
            view,
          ],
        );
      },
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.selected, required this.onSelected});

  final _InventorySort selected;
  final ValueChanged<_InventorySort> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<_InventorySort>(
      initialValue: selected,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      tooltip: 'Sort inventory',
      itemBuilder: (context) => _InventorySort.values
          .map((sort) {
            return PopupMenuItem<_InventorySort>(
              value: sort,
              child: Row(
                children: [
                  Icon(
                    sort.icon,
                    size: 20,
                    color: sort == selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(sort.label)),
                  if (sort == selected)
                    Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            );
          })
          .toList(growable: false),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected.icon, size: 19),
            const SizedBox(width: AppSpacing.xs),
            Text(selected.label, style: theme.textTheme.labelLarge),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.expand_more_rounded, size: 19),
          ],
        ),
      ),
    );
  }
}

IconData _departmentIcon(HotelDepartment department) => switch (department) {
  HotelDepartment.kitchen => Icons.soup_kitchen_outlined,
  HotelDepartment.housekeeping => Icons.cleaning_services_outlined,
  HotelDepartment.laundry => Icons.local_laundry_service_outlined,
  HotelDepartment.maintenance => Icons.build_outlined,
  HotelDepartment.reception => Icons.desk_outlined,
  HotelDepartment.office => Icons.business_center_outlined,
  HotelDepartment.publicArea => Icons.park_outlined,
  HotelDepartment.restaurant => Icons.restaurant_outlined,
  HotelDepartment.pool => Icons.pool_outlined,
  HotelDepartment.security => Icons.shield_outlined,
};

class _DepartmentFilterBar extends StatelessWidget {
  const _DepartmentFilterBar({
    required this.selected,
    required this.products,
    required this.archived,
    required this.onSelected,
  });

  final HotelDepartment? selected;
  final List<Product> products;
  final bool archived;
  final ValueChanged<HotelDepartment?> onSelected;

  @override
  Widget build(BuildContext context) {
    final relevantProducts = products
        .where((product) => product.isArchived == archived)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Department', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              ChoiceChip(
                selected: selected == null,
                showCheckmark: false,
                avatar: const Icon(Icons.domain_outlined, size: 17),
                label: Text('All departments  ${relevantProducts.length}'),
                onSelected: (_) => onSelected(null),
              ),
              for (final department in HotelDepartment.values)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: ChoiceChip(
                    selected: selected == department,
                    showCheckmark: false,
                    avatar: Icon(_departmentIcon(department), size: 17),
                    label: Text(
                      '${department.label}  '
                      '${relevantProducts.where((product) => product.department == department).length}',
                    ),
                    onSelected: (_) => onSelected(department),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DepartmentHeading extends StatelessWidget {
  const _DepartmentHeading({
    required this.department,
    required this.productCount,
  });

  final HotelDepartment department;
  final int productCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _departmentIcon(department),
            size: 20,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(department.label, style: theme.textTheme.titleMedium),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$productCount ${productCount == 1 ? 'item' : 'items'}',
            style: theme.textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final _InventoryFilter selected;
  final _InventoryCounts counts;
  final ValueChanged<_InventoryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: _InventoryFilter.values
            .map((filter) {
              return Padding(
                padding: EdgeInsets.only(
                  right: filter == _InventoryFilter.values.last
                      ? 0
                      : AppSpacing.xs,
                ),
                child: ChoiceChip(
                  selected: selected == filter,
                  showCheckmark: false,
                  avatar: Icon(filter.icon, size: 17),
                  label: Text(
                    '${filter.label}  ${AppFormatters.quantity(counts.forFilter(filter))}',
                  ),
                  onSelected: (_) => onSelected(filter),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _ResultsSummary extends StatelessWidget {
  const _ResultsSummary({
    required this.visibleCount,
    required this.totalCount,
    required this.sort,
  });

  final int visibleCount;
  final int totalCount;
  final _InventorySort sort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final countText = visibleCount == totalCount
        ? '$visibleCount ${visibleCount == 1 ? 'product' : 'products'}'
        : '$visibleCount of $totalCount products';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 6,
      children: [
        Text(
          countText,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          'Sorted by ${sort.label.toLowerCase()}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.settings,
    required this.onTap,
    required this.onRestock,
    this.compact = false,
  });

  final Product product;
  final StoreSettings settings;
  final ValueChanged<Product> onTap;
  final ValueChanged<Product> onRestock;
  final bool compact;

  String _money(int value, {bool compact = false}) {
    if (compact) {
      return AppFormatters.compactMoney(
        value,
        symbol: settings.currencySymbol,
        decimalDigits: settings.currencyDecimalDigits,
      );
    }
    return AppFormatters.money(
      value,
      symbol: settings.currencySymbol,
      decimalDigits: settings.currencyDecimalDigits,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _ProductStatus.from(product, context);
    final muted = product.isArchived;

    return Opacity(
      opacity: muted ? 0.72 : 1,
      child: SectionCard(
        onTap: () => onTap(product),
        semanticLabel:
            '${product.name}, ${product.department.label}, ${status.label}, '
            '${product.quantity} ${product.unit}, stock entered '
            '${AppFormatters.date(product.receivedAt.toLocal())}',
        padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
        borderColor: product.isLowStock || product.isOutOfStock
            ? status.color.withValues(alpha: 0.35)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.45,
                        ),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: Text(
                    AppFormatters.initials(product.name),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        product.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 8 : 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(
                  label: status.label,
                  color: status.color,
                  icon: status.icon,
                  compact: true,
                ),
                Text(
                  product.sku,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  _departmentIcon(product.department),
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    product.department.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Stock entered: '
              '${AppFormatters.date(product.receivedAt.toLocal())}',
              style: theme.textTheme.bodySmall,
            ),
            SizedBox(height: compact ? 8 : 12),
            const Divider(),
            SizedBox(height: compact ? 8 : 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ProductStat(
                    label: 'On hand',
                    value: '${AppFormatters.quantity(product.quantity)} units',
                    valueColor: status.color,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ProductStat(
                    label: 'Selling price',
                    value: _money(product.salePriceMinor, compact: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label:
                  'Low-stock alert at ${product.lowStockThreshold} ${product.unit}; ${product.quantity} available',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value:
                      (product.quantity /
                              (product.lowStockThreshold > 0
                                  ? product.lowStockThreshold * 2
                                  : (product.quantity > 0
                                        ? product.quantity
                                        : 1)))
                          .clamp(0.0, 1.0),
                  color: status.color,
                  backgroundColor: status.color.withValues(alpha: 0.10),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Low-stock alert: ${product.lowStockThreshold} units',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Retail stock value',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _money(product.retailValueMinor, compact: true),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
                if (!product.isArchived)
                  FilledButton.tonalIcon(
                    onPressed: () => onRestock(product),
                    icon: const Icon(Icons.add_box_outlined, size: 19),
                    label: const Text('Receive'),
                  )
                else
                  Text(
                    'Updated ${AppFormatters.relativeTime(product.updatedAt.toLocal())}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductStat extends StatelessWidget {
  const _ProductStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ProductStatus {
  const _ProductStatus(this.label, this.icon, this.color);

  factory _ProductStatus.from(Product product, BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    if (product.isArchived) {
      return _ProductStatus(
        'Archived',
        Icons.archive_outlined,
        theme.colorScheme.onSurfaceVariant,
      );
    }
    if (product.isOutOfStock) {
      return _ProductStatus(
        'Out',
        Icons.remove_circle_outline_rounded,
        theme.colorScheme.error,
      );
    }
    if (product.isLowStock) {
      return _ProductStatus(
        'Low',
        Icons.warning_amber_rounded,
        semantic.warning,
      );
    }
    return _ProductStatus(
      'In stock',
      Icons.check_circle_outline_rounded,
      semantic.success,
    );
  }

  final String label;
  final IconData icon;
  final Color color;
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss message',
              icon: const Icon(Icons.close_rounded),
              color: theme.colorScheme.onErrorContainer,
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryLoadingState extends StatelessWidget {
  const _InventoryLoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Semantics(
        label: 'Loading inventory',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Loading inventory…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
