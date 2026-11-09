import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../widgets/stock_date_field.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.controller, this.product});

  final InventoryController controller;
  final Product? product;

  bool get isEditing => product != null;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _categoryController;
  late final TextEditingController _unitController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _costController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _thresholdController;
  late HotelDepartment _department;
  late DateTime _receivedAt;
  bool _saving = false;
  bool _skuWasEdited = false;

  int get _decimalDigits => widget.controller.settings.currencyDecimalDigits;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(text: product?.name ?? '');
    _skuController = TextEditingController(text: product?.sku ?? '');
    _categoryController = TextEditingController(
      text: product?.category ?? 'General',
    );
    _unitController = TextEditingController(text: product?.unit ?? 'Each');
    _descriptionController = TextEditingController(
      text: product?.description ?? '',
    );
    _costController = TextEditingController(
      text: product == null
          ? ''
          : _moneyForInput(product.unitCostMinor, _decimalDigits),
    );
    _priceController = TextEditingController(
      text: product == null
          ? ''
          : _moneyForInput(product.salePriceMinor, _decimalDigits),
    );
    _stockController = TextEditingController(
      text: product == null ? '' : product.quantity.toString(),
    );
    _thresholdController = TextEditingController(
      text:
          (product?.lowStockThreshold ??
                  widget.controller.settings.defaultLowStockThreshold)
              .toString(),
    );
    _skuWasEdited = product != null;
    _department = product?.department ?? HotelDepartment.kitchen;
    _receivedAt = product?.receivedAt ?? DateUtils.dateOnly(DateTime.now());
    _nameController.addListener(_suggestSku);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_suggestSku)
      ..dispose();
    _skuController.dispose();
    _categoryController.dispose();
    _unitController.dispose();
    _descriptionController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _suggestSku() {
    if (_skuWasEdited || widget.isEditing) return;
    final words = _nameController.text
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      _skuController.clear();
      return;
    }
    final prefix = words.length == 1
        ? words.first.substring(0, math.min(4, words.first.length))
        : words.take(3).map((word) => word[0]).join();
    final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(
      9,
    );
    _skuController.text = '$prefix-$suffix';
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final original = widget.product;
    if (original != null && original.department != _department) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change stock department?'),
          content: Text(
            '${original.quantity} remaining units of ${original.name} will belong to '
            '${_department.label} instead of ${original.department.label}. '
            'Previous deliveries and usage keep their original department.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Change department'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }

    setState(() => _saving = true);
    try {
      final product = widget.product;
      final draft = ProductDraft(
        name: _nameController.text.trim(),
        sku: _skuController.text.trim().toUpperCase(),
        category: _categoryController.text.trim(),
        department: _department,
        unit: _unitController.text.trim(),
        receivedAt: _receivedAt,
        description: _descriptionController.text.trim(),
        initialStock:
            product?.quantity ??
            int.parse(
              _stockController.text.trim().isEmpty
                  ? '0'
                  : _stockController.text.trim(),
            ),
        unitCostMinor: _parseMoney(_costController.text, _decimalDigits),
        salePriceMinor: _parseMoney(_priceController.text, _decimalDigits),
        lowStockThreshold: int.parse(_thresholdController.text.trim()),
      );

      if (product == null) {
        await widget.controller.addProduct(draft);
      } else {
        await widget.controller.updateProduct(product.id, draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            product == null
                ? '${draft.name} added to inventory'
                : '${draft.name} updated',
          ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final currency = widget.controller.settings.currencyCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit product' : 'Add product'),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              _FormSection(
                icon: Icons.inventory_2_outlined,
                title: 'Product details',
                subtitle: 'How this item appears across your inventory.',
                children: [
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Product name',
                      hintText: 'e.g. Premium rice 5 kg',
                      prefixIcon: Icon(Icons.sell_outlined),
                    ),
                    validator: _required('Enter a product name'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<HotelDepartment>(
                    initialValue: _department,
                    decoration: const InputDecoration(
                      labelText: 'Hotel department',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                      helperText:
                          'Stock and usage are managed in this department.',
                      helperMaxLines: 2,
                    ),
                    items: HotelDepartment.values
                        .map(
                          (department) => DropdownMenuItem(
                            value: department,
                            child: Text(department.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) setState(() => _department = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _skuController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'SKU',
                      hintText: 'Unique stock code',
                      prefixIcon: const Icon(Icons.qr_code_2),
                      suffixIcon: IconButton(
                        tooltip: 'Generate SKU',
                        onPressed: () {
                          _skuWasEdited = false;
                          _suggestSku();
                        },
                        icon: const Icon(Icons.auto_awesome_outlined),
                      ),
                    ),
                    onChanged: (_) => _skuWasEdited = true,
                    validator: _required('Enter or generate a SKU'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _categoryController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      hintText: 'e.g. Groceries',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    validator: _required('Enter a category'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _unitController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Unit of measure',
                      hintText: 'e.g. bottle, kg, pack, piece',
                      prefixIcon: Icon(Icons.straighten_outlined),
                    ),
                    validator: _required('Enter a unit of measure'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Size, brand, location, or other details',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FormSection(
                icon: Icons.payments_outlined,
                title: 'Pricing',
                subtitle: 'Use $currency values for cost and selling price.',
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _MoneyField(
                          controller: _costController,
                          label: 'Cost price',
                          currency: currency,
                          decimalDigits: _decimalDigits,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MoneyField(
                          controller: _priceController,
                          label: 'Selling price',
                          currency: currency,
                          decimalDigits: _decimalDigits,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FormSection(
                icon: Icons.stacked_bar_chart_outlined,
                title: 'Stock control',
                subtitle: widget.isEditing
                    ? 'Use Receive stock or Adjust stock to change quantity.'
                    : 'Set the opening quantity and alert threshold.',
                children: [
                  StockDateField(
                    value: _receivedAt,
                    label: 'Stock entered date',
                    helperText: widget.isEditing
                        ? 'Original entry date is kept. Use Receive stock for each new delivery.'
                        : 'Choose the date this opening stock arrived.',
                    onChanged: widget.isEditing || _saving
                        ? null
                        : (date) => setState(() => _receivedAt = date),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stockController,
                          enabled: !widget.isEditing,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Opening stock',
                            prefixIcon: Icon(Icons.inventory_outlined),
                          ),
                          validator: (value) => _nonNegativeInteger(
                            value,
                            'Enter a valid quantity',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _thresholdController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Low-stock alert',
                            prefixIcon: Icon(Icons.notifications_none),
                          ),
                          validator: (value) =>
                              _nonNegativeInteger(value, 'Enter a valid level'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: .45,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Sales and department usage reduce available stock. '
                            'Each new delivery adds stock to this department '
                            'and keeps its own arrival date and history.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(widget.isEditing ? Icons.check : Icons.add),
            label: Text(widget.isEditing ? 'Save changes' : 'Add product'),
          ),
        ),
      ),
    );
  }

  FormFieldValidator<String> _required(String message) {
    return (value) => value == null || value.trim().isEmpty ? message : null;
  }

  String? _nonNegativeInteger(String? value, String message) {
    final parsed = int.tryParse(value?.trim().isEmpty ?? true ? '0' : value!);
    return parsed == null || parsed < 0 ? message : null;
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.currency,
    required this.decimalDigits,
  });

  final TextEditingController controller;
  final String label;
  final String currency;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimalDigits > 0),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimalDigits > 0 ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: InputDecoration(labelText: label, prefixText: '$currency '),
      validator: (value) {
        try {
          final amount = _parseMoney(value ?? '', decimalDigits);
          return amount < 0 ? 'Cannot be negative' : null;
        } catch (_) {
          return 'Enter a valid price';
        }
      },
    );
  }
}

int _parseMoney(String raw, int decimalDigits) {
  final value = raw.trim().replaceAll(',', '');
  if (value.isEmpty) return 0;
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
    throw const FormatException('Invalid money value');
  }
  final parts = value.split('.');
  if (parts.length > 1 && parts[1].length > decimalDigits) {
    throw const FormatException('Too many decimal places');
  }
  final scale = List<int>.filled(
    decimalDigits,
    10,
  ).fold<int>(1, (a, b) => a * b);
  final whole = int.parse(parts.first) * scale;
  if (decimalDigits == 0) return whole;
  final fraction = parts.length == 1
      ? 0
      : int.parse(parts[1].padRight(decimalDigits, '0'));
  return whole + fraction;
}

String _moneyForInput(int minor, int decimalDigits) {
  if (decimalDigits == 0) return minor.toString();
  final scale = List<int>.filled(
    decimalDigits,
    10,
  ).fold<int>(1, (a, b) => a * b);
  final whole = minor ~/ scale;
  final fraction = (minor % scale).toString().padLeft(decimalDigits, '0');
  return '$whole.$fraction';
}
