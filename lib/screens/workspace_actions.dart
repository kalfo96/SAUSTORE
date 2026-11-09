import 'package:flutter/material.dart';

import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../widgets/app_widgets.dart';

enum WorkspaceAction { receive, usage, product, sale }

Future<WorkspaceAction?> showWorkspaceActions(BuildContext context) {
  return showModalBottomSheet<WorkspaceAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            eyebrow: 'Make a move',
            title: 'Quick actions',
            subtitle:
                'A clear record for everything that comes in or goes out.',
          ),
          const SizedBox(height: 20),
          for (final entry in [
            (
              WorkspaceAction.receive,
              Icons.add_box_outlined,
              'Receive delivery',
              'Add stock with its arrival date',
            ),
            (
              WorkspaceAction.usage,
              Icons.assignment_outlined,
              'Request stock',
              'Submit a department request for approval',
            ),
            (
              WorkspaceAction.product,
              Icons.inventory_2_outlined,
              'Add stock item',
              'Assign a product to a department',
            ),
            (
              WorkspaceAction.sale,
              Icons.point_of_sale_outlined,
              'Record sale',
              'Create a sale with a stock trail',
            ),
          ]) ...[
            SectionCard(
              onTap: () => Navigator.pop(sheetContext, entry.$1),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(entry.$2),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.$3,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.$4,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.north_east_rounded, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}

Future<int?> showWorkspaceMenu(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'Your workspace',
            subtitle: 'Everything else, one tap away.',
          ),
          const SizedBox(height: 16),
          for (final entry in [
            (
              2,
              Icons.point_of_sale_rounded,
              'Sell',
              'Record a sale and reduce stock',
            ),
            (
              5,
              Icons.history_rounded,
              'Activity',
              'View your stock movement timeline',
            ),
            (
              6,
              Icons.assignment_outlined,
              'Requisitions',
              'Approve, issue and confirm department requests',
            ),
            (
              7,
              Icons.tune_rounded,
              'Settings',
              'Appearance, backups, and store details',
            ),
          ])
            ListTile(
              leading: Icon(entry.$2),
              title: Text(entry.$3),
              subtitle: Text(entry.$4),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(sheetContext, entry.$1),
            ),
        ],
      ),
    ),
  );
}

Future<Product?> showReceiveProductPicker(
  BuildContext context, {
  required InventoryController controller,
}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReceiveProductPicker(controller: controller),
  );
}

class _ReceiveProductPicker extends StatefulWidget {
  const _ReceiveProductPicker({required this.controller});
  final InventoryController controller;
  @override
  State<_ReceiveProductPicker> createState() => _ReceiveProductPickerState();
}

class _ReceiveProductPickerState extends State<_ReceiveProductPicker> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .85,
    child: AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _search]),
      builder: (context, _) {
        final query = _search.text.trim().toLowerCase();
        final products = widget.controller.activeProducts
            .where(
              (p) => '${p.name} ${p.sku} ${p.department.label}'
                  .toLowerCase()
                  .contains(query),
            )
            .toList();
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'Receive delivery',
                subtitle: 'Which stock item has arrived?',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Search stock or department',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: products.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching stock items. Try another name or SKU.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: products.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return SectionCard(
                            onTap: () => Navigator.pop(context, product),
                            child: Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${product.department.label} · ${product.quantity} on hand',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.add_circle_outline_rounded),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
