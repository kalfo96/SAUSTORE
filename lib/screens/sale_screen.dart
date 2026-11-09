import 'package:flutter/material.dart';

import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'screen_helpers.dart';

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({
    super.key,
    required this.controller,
    this.initialProductId,
    this.standalone = false,
    this.onSaleCompleted,
    this.onAddProduct,
    this.onLoadStarterInventory,
  });

  final InventoryController controller;
  final String? initialProductId;
  final bool standalone;
  final ValueChanged<SaleRecord>? onSaleCompleted;
  final VoidCallback? onAddProduct;
  final VoidCallback? onLoadStarterInventory;

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final Map<String, int> _quantities = <String, int>{};
  final _customerController = TextEditingController();
  final _referenceController = TextEditingController();
  final _noteController = TextEditingController();
  String _paymentMethod = 'Cash';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final productId = widget.initialProductId;
    final product = productId == null
        ? null
        : widget.controller.productById(productId);
    if (product != null && !product.isArchived && product.quantity > 0) {
      _quantities[product.id] = 1;
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<Product> get _cartProducts {
    return _quantities.keys
        .map(widget.controller.productById)
        .whereType<Product>()
        .toList(growable: false);
  }

  int get _totalMinor => _cartProducts.fold<int>(0, (total, product) {
    return total + product.salePriceMinor * (_quantities[product.id] ?? 0);
  });

  Future<void> _pickProduct() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductPickerSheet(
        products: widget.controller.activeProducts
            .where((product) => product.quantity > 0)
            .toList(),
        selectedIds: _quantities.keys.toSet(),
        controller: widget.controller,
      ),
    );
    if (product == null || !mounted) return;
    setState(() {
      _quantities.update(
        product.id,
        (quantity) => quantity < product.quantity ? quantity + 1 : quantity,
        ifAbsent: () => 1,
      );
    });
  }

  Future<void> _recordSale() async {
    final products = _cartProducts;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one product to this sale.')),
      );
      return;
    }
    for (final product in products) {
      final quantity = _quantities[product.id] ?? 0;
      if (quantity > product.quantity) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${product.name} now has only ${product.quantity} ${product.unit} available.',
            ),
          ),
        );
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.point_of_sale_outlined),
        title: const Text('Complete this sale?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${products.length} product${products.length == 1 ? '' : 's'} '
              'and ${_quantities.values.fold<int>(0, (a, b) => a + b)} total units',
            ),
            const SizedBox(height: 12),
            Text(
              formatMoney(widget.controller, _totalMinor),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Stock will be reduced immediately and an audit record will be created.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Complete sale'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final sale = await widget.controller.recordSale(
        products
            .map(
              (product) => SaleItemInput(
                productId: product.id,
                quantity: _quantities[product.id]!,
              ),
            )
            .toList(),
        reference: _referenceController.text.trim(),
        customerName: _customerController.text.trim(),
        paymentMethod: _paymentMethod,
        note: _noteController.text.trim(),
      );
      if (!mounted) return;
      widget.onSaleCompleted?.call(sale);
      await _showSuccess(sale);
      if (!mounted) return;
      if (widget.standalone) {
        Navigator.pop(context, sale);
      } else {
        setState(() {
          _quantities.clear();
          _customerController.clear();
          _referenceController.clear();
          _noteController.clear();
          _paymentMethod = 'Cash';
        });
      }
    } on InventoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSuccess(SaleRecord sale) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.check_circle,
          color: dialogContext.semanticColors.success,
          size: 44,
        ),
        title: const Text('Sale recorded'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sale.receiptNumber,
              style: Theme.of(dialogContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              formatMoney(widget.controller, sale.totalMinor),
              style: Theme.of(dialogContext).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text('${sale.totalUnits} units deducted from stock'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final products = _cartProducts;
        return SafeArea(
          top: widget.standalone,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  context.pagePadding.left,
                  20,
                  context.pagePadding.right,
                  130,
                ),
                sliver: SliverList.list(
                  children: [
                    PageHeader(
                      eyebrow: 'Checkout',
                      title: 'New sale',
                      subtitle:
                          'Add products, confirm quantities, then record payment.',
                      action: FilledButton.tonalIcon(
                        onPressed:
                            widget.controller.activeProducts.any(
                              (product) => product.quantity > 0,
                            )
                            ? _pickProduct
                            : null,
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Add product'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (products.isEmpty)
                      SectionCard(
                        child: EmptyState(
                          compact: true,
                          icon: Icons.shopping_cart_outlined,
                          title: widget.controller.activeProducts.isEmpty
                              ? 'No products to sell'
                              : 'Your sale is empty',
                          message: widget.controller.activeProducts.isEmpty
                              ? 'Add inventory before recording your first sale.'
                              : widget.controller.activeProducts.every(
                                  (product) => product.quantity == 0,
                                )
                              ? 'All products are out of stock. Receive stock first.'
                              : 'Choose a product to start this sale.',
                          action: widget.controller.activeProducts.isEmpty
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.onAddProduct != null)
                                      FilledButton.icon(
                                        onPressed: widget.onAddProduct,
                                        icon: const Icon(
                                          Icons.add_box_outlined,
                                        ),
                                        label: const Text('Add first product'),
                                      ),
                                    if (widget.onLoadStarterInventory !=
                                        null) ...[
                                      const SizedBox(height: 8),
                                      OutlinedButton.icon(
                                        onPressed:
                                            widget.onLoadStarterInventory,
                                        icon: const Icon(
                                          Icons.auto_awesome_outlined,
                                        ),
                                        label: const Text(
                                          'Load hotel starter stock',
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : widget.controller.activeProducts.every(
                                  (product) => product.quantity == 0,
                                )
                              ? null
                              : FilledButton.icon(
                                  onPressed: _pickProduct,
                                  icon: const Icon(Icons.add_shopping_cart),
                                  label: const Text('Choose product'),
                                ),
                        ),
                      )
                    else ...[
                      const SectionHeader(
                        title: 'Sale items',
                        subtitle: 'Quantities cannot exceed available stock.',
                      ),
                      const SizedBox(height: 12),
                      SectionCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < products.length;
                              index++
                            ) ...[
                              _CartLine(
                                product: products[index],
                                quantity: _quantities[products[index].id]!,
                                controller: widget.controller,
                                onChanged: (quantity) => setState(() {
                                  _quantities[products[index].id] = quantity;
                                }),
                                onRemove: () => setState(() {
                                  _quantities.remove(products[index].id);
                                }),
                              ),
                              if (index != products.length - 1)
                                const Divider(indent: 16, endIndent: 16),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const SectionHeader(
                        title: 'Sale details',
                        subtitle:
                            'Optional information makes records easier to find.',
                      ),
                      const SizedBox(height: 12),
                      SectionCard(
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _paymentMethod,
                              decoration: const InputDecoration(
                                labelText: 'Payment method',
                                prefixIcon: Icon(
                                  Icons.account_balance_wallet_outlined,
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Cash',
                                  child: Text('Cash'),
                                ),
                                DropdownMenuItem(
                                  value: 'Mobile money',
                                  child: Text('Mobile money'),
                                ),
                                DropdownMenuItem(
                                  value: 'Card',
                                  child: Text('Card'),
                                ),
                                DropdownMenuItem(
                                  value: 'Credit',
                                  child: Text('Credit'),
                                ),
                                DropdownMenuItem(
                                  value: 'Other',
                                  child: Text('Other'),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _paymentMethod = value!),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _customerController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Customer name (optional)',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _referenceController,
                              decoration: const InputDecoration(
                                labelText: 'Receipt reference (optional)',
                                prefixIcon: Icon(Icons.receipt_long_outlined),
                                helperText:
                                    'A receipt number is generated if left blank',
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _noteController,
                              textCapitalization: TextCapitalization.sentences,
                              minLines: 2,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Note (optional)',
                                prefixIcon: Icon(Icons.notes),
                                alignLabelWithHint: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SaleSummary(
                        productCount: products.length,
                        unitCount: _quantities.values.fold<int>(
                          0,
                          (total, value) => total + value,
                        ),
                        total: formatMoney(widget.controller, _totalMinor),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _saving ? null : _recordSale,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _saving
                              ? 'Recording sale...'
                              : 'Review and complete sale',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!widget.standalone) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Record sale')),
      body: content,
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.product,
    required this.quantity,
    required this.controller,
    required this.onChanged,
    required this.onRemove,
  });

  final Product product;
  final int quantity;
  final InventoryController controller;
  final ValueChanged<int> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductAvatar(product: product),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${product.sku}  |  ${product.quantity} ${product.unit} available',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remove ${product.name}',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              QuantityStepper(
                value: quantity,
                min: 1,
                max: product.quantity,
                onChanged: onChanged,
                compact: true,
                label: '${product.name} quantity',
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(controller, product.salePriceMinor * quantity),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${formatMoney(controller, product.salePriceMinor)} each',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaleSummary extends StatelessWidget {
  const _SaleSummary({
    required this.productCount,
    required this.unitCount,
    required this.total,
  });

  final int productCount;
  final int unitCount;
  final String total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      backgroundColor: scheme.primaryContainer,
      borderColor: scheme.primary.withValues(alpha: .2),
      child: Row(
        children: [
          Icon(Icons.receipt_long, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$productCount products  |  $unitCount units',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          Text(
            total,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: scheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({
    required this.products,
    required this.selectedIds,
    required this.controller,
  });

  final List<Product> products;
  final Set<String> selectedIds;
  final InventoryController controller;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.products.where((product) {
      final query = _query.trim().toLowerCase();
      return query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
    }).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageHeader(
                  title: 'Choose a product',
                  subtitle: 'Only products with available stock are shown.',
                ),
                const SizedBox(height: 16),
                AppSearchField(
                  autofocus: true,
                  hintText: 'Search name, SKU, or category',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: matches.isEmpty
                ? const EmptyState(
                    compact: true,
                    icon: Icons.search_off,
                    title: 'No matching products',
                    message: 'Try another name, SKU, or category.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final product = matches[index];
                      final selected = widget.selectedIds.contains(product.id);
                      return ListTile(
                        onTap: () => Navigator.pop(context, product),
                        leading: ProductAvatar(product: product, size: 44),
                        title: Text(product.name),
                        subtitle: Text(
                          '${product.sku}  |  ${product.quantity} ${product.unit} available',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatMoney(
                                widget.controller,
                                product.salePriceMinor,
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (selected)
                              Text(
                                'Already added',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
