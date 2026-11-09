import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/stock_date_field.dart';
import 'screen_helpers.dart';

Future<bool?> showRestockSheet(
  BuildContext context, {
  required InventoryController controller,
  required Product product,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RestockSheet(controller: controller, product: product),
  );
}

Future<bool?> showAdjustStockSheet(
  BuildContext context, {
  required InventoryController controller,
  required Product product,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AdjustStockSheet(controller: controller, product: product),
  );
}

class _RestockSheet extends StatefulWidget {
  const _RestockSheet({required this.controller, required this.product});

  final InventoryController controller;
  final Product product;

  @override
  State<_RestockSheet> createState() => _RestockSheetState();
}

class _RestockSheetState extends State<_RestockSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  final _supplierController = TextEditingController();
  final _invoiceController = TextEditingController();
  late final TextEditingController _costController;
  bool _saving = false;
  int _previewQuantity = 0;
  DateTime _receivedAt = DateUtils.dateOnly(DateTime.now());
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _previewQuantity = widget.product.quantity;
    _costController = TextEditingController(
      text: moneyInputValue(
        widget.product.unitCostMinor,
        widget.controller.settings.currencyDecimalDigits,
      ),
    );
    _quantityController.addListener(_updatePreview);
    _costController.addListener(_updatePreview);
  }

  void _updatePreview() {
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    setState(() => _previewQuantity = widget.product.quantity + quantity);
  }

  void _addQuantity(int amount) {
    _quantityController.text =
        '${(int.tryParse(_quantityController.text) ?? 0) + amount}';
  }

  @override
  void dispose() {
    _quantityController
      ..removeListener(_updatePreview)
      ..dispose();
    _costController
      ..removeListener(_updatePreview)
      ..dispose();
    _noteController.dispose();
    _supplierController.dispose();
    _invoiceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.controller.restockProduct(
        widget.product.id,
        int.parse(_quantityController.text),
        parseMoneyInput(
          _costController.text,
          widget.controller.settings.currencyDecimalDigits,
        ),
        note: _noteController.text.trim(),
        receivedAt: _receivedAt,
        supplierName: _supplierController.text.trim(),
        invoiceNumber: _invoiceController.text.trim(),
        expiryDate: _expiryDate,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Delivery saved · central stock updated.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } on InventoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                eyebrow: 'Stock in',
                title: 'Receive new stock',
                subtitle:
                    'Record a delivery without overwriting the audit trail.',
              ),
              const SizedBox(height: 20),
              SectionCard(
                child: Row(
                  children: [
                    ProductAvatar(product: widget.product),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${widget.product.sku}  |  '
                            '${widget.product.quantity} ${widget.product.unit} currently',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'Usual department: ${widget.product.department.label}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              StockDateField(
                value: _receivedAt,
                label: 'Delivery arrival date',
                helperText:
                    'Each delivery keeps its own date, quantity, and cost.',
                onChanged: _saving
                    ? null
                    : (date) => setState(() {
                        _receivedAt = date;
                        if (_expiryDate != null &&
                            _expiryDate!.isBefore(date)) {
                          _expiryDate = null;
                        }
                      }),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _supplierController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Supplier',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _invoiceController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Invoice number',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate:
                              _expiryDate != null &&
                                  !_expiryDate!.isBefore(_receivedAt)
                              ? _expiryDate!
                              : _receivedAt,
                          firstDate: _receivedAt,
                          lastDate: DateTime(2100),
                          helpText: 'Select expiry date',
                        );
                        if (selected != null && mounted) {
                          setState(() => _expiryDate = selected);
                        }
                      },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _expiryDate == null
                      ? 'Expiry date (optional)'
                      : 'Expires ${_expiryDate!.year.toString().padLeft(4, '0')}-'
                            '${_expiryDate!.month.toString().padLeft(2, '0')}-'
                            '${_expiryDate!.day.toString().padLeft(2, '0')}',
                ),
              ),
              if (_expiryDate != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _expiryDate = null),
                    child: const Text('Remove expiry date'),
                  ),
                ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _quantityController,
                enabled: !_saving,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Quantity received',
                  prefixIcon: Icon(Icons.add_box_outlined),
                ),
                validator: (value) {
                  final quantity = int.tryParse(value ?? '');
                  return quantity == null || quantity <= 0
                      ? 'Enter a quantity greater than zero'
                      : null;
                },
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final amount in [5, 10, 20])
                    ActionChip(
                      label: Text('+$amount'),
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      onPressed: _saving ? null : () => _addQuantity(amount),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _costController,
                enabled: !_saving,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: settings.currencyDecimalDigits > 0,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Unit cost',
                  prefixText: '${settings.currencyCode} ',
                  helperText: 'Recorded with this purchase receipt',
                ),
                validator: (value) {
                  try {
                    parseMoneyInput(
                      value ?? '',
                      settings.currencyDecimalDigits,
                    );
                    return null;
                  } catch (_) {
                    return 'Enter a valid cost';
                  }
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Additional note (optional)',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.trending_up),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${widget.product.quantity} ${widget.product.unit} current  ->  '
                        '$_previewQuantity ${widget.product.unit} after delivery',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.inventory_2_outlined),
                label: const Text('Add to stock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdjustStockSheet extends StatefulWidget {
  const _AdjustStockSheet({required this.controller, required this.product});

  final InventoryController controller;
  final Product product;

  @override
  State<_AdjustStockSheet> createState() => _AdjustStockSheetState();
}

class _AdjustStockSheetState extends State<_AdjustStockSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantityController;
  final _noteController = TextEditingController();
  String _reason = 'Stock count correction';
  bool _saving = false;

  static const reasons = <String>[
    'Stock count correction',
    'Damaged stock',
    'Expired stock',
    'Lost stock',
    'Returned stock',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.product.quantity.toString(),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final details = _noteController.text.trim();
      await widget.controller.adjustStock(
        widget.product.id,
        int.parse(_quantityController.text),
        note: details.isEmpty ? _reason : '$_reason: $details',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on InventoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entered = int.tryParse(_quantityController.text);
    final delta = entered == null ? 0 : entered - widget.product.quantity;
    final color = delta < 0
        ? Theme.of(context).colorScheme.error
        : context.semanticColors.success;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                eyebrow: 'Correction',
                title: 'Adjust stock count',
                subtitle:
                    'Use the physical count you have verified. The reason is saved.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Use an approved store requisition for department consumption. '
                'Adjustments are for verified count corrections, damaged, lost, '
                'expired or returned stock only.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _quantityController,
                enabled: !_saving,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'New central-store quantity',
                  helperText: '${widget.product.quantity} currently recorded',
                  prefixIcon: const Icon(Icons.numbers),
                ),
                validator: (value) {
                  final quantity = int.tryParse(value ?? '');
                  if (quantity == null || quantity < 0) {
                    return 'Enter zero or a positive quantity';
                  }
                  if (quantity == widget.product.quantity) {
                    return 'Enter a different quantity';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _reason = value);
                      },
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  prefixIcon: Icon(Icons.fact_check_outlined),
                ),
                items: reasons
                    .map(
                      (reason) =>
                          DropdownMenuItem(value: reason, child: Text(reason)),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _reason == 'Other'
                      ? 'Explanation'
                      : 'Additional note (optional)',
                  prefixIcon: const Icon(Icons.notes),
                ),
                validator: (value) =>
                    _reason == 'Other' &&
                        (value == null || value.trim().isEmpty)
                    ? 'Explain this adjustment'
                    : null,
              ),
              const SizedBox(height: 16),
              SectionCard(
                backgroundColor: color.withValues(alpha: .08),
                borderColor: color.withValues(alpha: .24),
                child: Row(
                  children: [
                    Icon(
                      delta < 0 ? Icons.trending_down : Icons.trending_up,
                      color: color,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        delta == 0
                            ? 'Enter the verified quantity'
                            : '${delta > 0 ? '+' : ''}$delta ${widget.product.unit}  |  '
                                  '${entered ?? widget.product.quantity} ${widget.product.unit} after adjustment',
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(color: color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Save adjustment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
