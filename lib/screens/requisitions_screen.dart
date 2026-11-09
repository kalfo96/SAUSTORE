import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inventory_models.dart';
import '../services/store_issue_form.dart';
import '../state/inventory_controller.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';

class RequisitionsScreen extends StatelessWidget {
  const RequisitionsScreen({
    super.key,
    required this.controller,
    required this.actorName,
  });

  final InventoryController controller;
  final String actorName;

  Future<void> _create(BuildContext context) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _NewRequisitionSheet(controller: controller, actorName: actorName),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Requisition submitted for approval.')),
      );
    }
  }

  Future<void> _printForm(
    BuildContext context, {
    StoreRequisition? requisition,
  }) async {
    try {
      await printStoreIssueForm(
        hotelName: controller.settings.storeName,
        requisition: requisition,
      );
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open print preview: $error')),
        );
      }
    }
  }

  Future<void> _advance(
    BuildContext context,
    StoreRequisition requisition,
  ) async {
    try {
      switch (requisition.status) {
        case RequisitionStatus.requested:
          await controller.approveRequisition(
            requisition.id,
            approvedBy: actorName,
          );
        case RequisitionStatus.approved:
          await controller.issueRequisition(
            requisition.id,
            issuedBy: actorName,
          );
        case RequisitionStatus.issued:
          await controller.confirmRequisitionReceived(
            requisition.id,
            receivedBy: actorName,
          );
        case RequisitionStatus.received:
        case RequisitionStatus.rejected:
          return;
      }
    } on InventoryException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _reject(
    BuildContext context,
    StoreRequisition requisition,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final reasonController = TextEditingController();
        return AlertDialog(
          title: const Text('Reject requisition'),
          content: TextField(
            controller: reasonController,
            autofocus: true,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = reasonController.text.trim();
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
    if (reason == null || !context.mounted) return;
    try {
      await controller.rejectRequisition(
        requisition.id,
        rejectedBy: actorName,
        reason: reason,
      );
    } on InventoryException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Store requisitions'),
      actions: [
        IconButton(
          tooltip: 'Print blank store form',
          onPressed: () => _printForm(context),
          icon: const Icon(Icons.print_outlined),
        ),
        IconButton(
          tooltip: 'New requisition',
          onPressed: () => _create(context),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final requisitions = controller.requisitions.toList()
          ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
        if (requisitions.isEmpty) {
          return EmptyState(
            icon: Icons.assignment_outlined,
            title: 'No store requisitions yet',
            message:
                'Department requests will appear here for approval, issue and receipt confirmation.',
            actionLabel: 'Print blank form',
            actionIcon: Icons.print_outlined,
            onAction: () => _printForm(context),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: requisitions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final requisition = requisitions[index];
            return _RequisitionCard(
              requisition: requisition,
              onAdvance: () => _advance(context, requisition),
              onReject: () => _reject(context, requisition),
              onPrint: () => _printForm(context, requisition: requisition),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _create(context),
      icon: const Icon(Icons.post_add_outlined),
      label: const Text('Request stock'),
    ),
  );
}

class _NewRequisitionSheet extends StatefulWidget {
  const _NewRequisitionSheet({
    required this.controller,
    required this.actorName,
  });

  final InventoryController controller;
  final String actorName;

  @override
  State<_NewRequisitionSheet> createState() => _NewRequisitionSheetState();
}

class _NewRequisitionSheetState extends State<_NewRequisitionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _requester;
  final _note = TextEditingController();
  final List<SaleItemInput> _items = [];
  HotelDepartment _department = HotelDepartment.housekeeping;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _requester = TextEditingController(text: widget.actorName);
  }

  @override
  void dispose() {
    _requester.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final item = await showModalBottomSheet<SaleItemInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddRequisitionLineSheet(
        products: widget.controller.activeProducts.toList(),
      ),
    );
    if (item == null || !mounted) return;
    setState(() {
      final index = _items.indexWhere(
        (existing) => existing.productId == item.productId,
      );
      if (index < 0) {
        _items.add(item);
      } else {
        final existing = _items[index];
        _items[index] = SaleItemInput(
          productId: existing.productId,
          quantity: existing.quantity + item.quantity,
        );
      }
    });
  }

  Future<void> _submit() async {
    if (_saving ||
        !(_formKey.currentState?.validate() ?? false) ||
        _items.isEmpty) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.createRequisition(
        department: _department,
        requestedBy: _requester.text,
        items: _items,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
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
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              eyebrow: 'Department request',
              title: 'Request stock',
              subtitle:
                  'Requests must be approved before the store can issue stock.',
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<HotelDepartment>(
              initialValue: _department,
              decoration: const InputDecoration(
                labelText: 'Department',
                prefixIcon: Icon(Icons.apartment_outlined),
              ),
              items: HotelDepartment.values
                  .map(
                    (department) => DropdownMenuItem(
                      value: department,
                      child: Text(department.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (department) {
                      if (department != null) {
                        setState(() => _department = department);
                      }
                    },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _requester,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Requested by',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter the requester name'
                  : null,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Requested items',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
              ],
            ),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('Add one or more items to continue.'),
              ),
            for (final item in _items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.controller.productById(item.productId)?.name ??
                      'Unavailable item',
                ),
                subtitle: Text('Quantity: ${item.quantity}'),
                trailing: IconButton(
                  tooltip: 'Remove item',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _items.remove(item)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 300,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Purpose / note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving || _items.isEmpty ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Submit for approval'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AddRequisitionLineSheet extends StatefulWidget {
  const _AddRequisitionLineSheet({required this.products});
  final List<Product> products;

  @override
  State<_AddRequisitionLineSheet> createState() =>
      _AddRequisitionLineSheetState();
}

class _AddRequisitionLineSheetState extends State<_AddRequisitionLineSheet> {
  final _quantity = TextEditingController(text: '1');
  String? _productId;

  @override
  void initState() {
    super.initState();
    if (widget.products.isNotEmpty) _productId = widget.products.first.id;
  }

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Add requested item',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _productId,
          decoration: const InputDecoration(labelText: 'Stock item'),
          items: widget.products
              .map(
                (product) => DropdownMenuItem(
                  value: product.id,
                  child: Text(
                    '${product.name} (${product.quantity} ${product.unit})',
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (value) => setState(() => _productId = value),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _quantity,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Quantity requested'),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () {
            final quantity = int.tryParse(_quantity.text);
            if (_productId == null || quantity == null || quantity <= 0) return;
            Navigator.pop(
              context,
              SaleItemInput(productId: _productId!, quantity: quantity),
            );
          },
          child: const Text('Add to request'),
        ),
      ],
    ),
  );
}

class _RequisitionCard extends StatelessWidget {
  const _RequisitionCard({
    required this.requisition,
    required this.onAdvance,
    required this.onReject,
    required this.onPrint,
  });

  final StoreRequisition requisition;
  final VoidCallback onAdvance;
  final VoidCallback onReject;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (requisition.status) {
      RequisitionStatus.requested => Theme.of(context).colorScheme.tertiary,
      RequisitionStatus.approved => Theme.of(context).colorScheme.primary,
      RequisitionStatus.issued => Colors.orange.shade800,
      RequisitionStatus.received => Colors.green.shade700,
      RequisitionStatus.rejected => Theme.of(context).colorScheme.error,
    };
    final nextAction = switch (requisition.status) {
      RequisitionStatus.requested => 'Approve request',
      RequisitionStatus.approved => 'Issue stock',
      RequisitionStatus.issued => 'Confirm receipt',
      RequisitionStatus.received || RequisitionStatus.rejected => null,
    };
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  requisition.department.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(
                label: Text(requisition.status.label),
                labelStyle: TextStyle(color: statusColor),
                side: BorderSide(color: statusColor.withValues(alpha: .4)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text(
            'Requested by ${requisition.requestedBy} · '
            '${AppFormatters.dateTime(requisition.requestedAt.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final line in requisition.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${line.productName} · ${line.quantity} ${line.unit}',
              ),
            ),
          if (requisition.note != null) ...[
            const SizedBox(height: 6),
            Text(
              requisition.note!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Approval: ${requisition.approvedBy ?? '—'}  ·  '
            'Issued: ${requisition.issuedBy ?? '—'}  ·  '
            'Received: ${requisition.receivedBy ?? '—'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onPrint,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print form'),
            ),
          ),
          if (nextAction != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (requisition.status == RequisitionStatus.requested)
                  TextButton(onPressed: onReject, child: const Text('Reject')),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: onAdvance,
                  child: Text(nextAction),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
