import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/inventory_models.dart';
import '../state/inventory_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final InventoryController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final settings = controller.settings;
        return SafeArea(
          top: false,
          child: ListView(
            padding: context.pagePadding.copyWith(bottom: 40),
            children: [
              PageHeader(
                eyebrow: 'Configuration',
                title: 'Settings & backup',
                subtitle: AppConfig.usesLiveBackend
                    ? 'Manage the shared hotel inventory, backups, and display preferences.'
                    : 'Manage display preferences and protect the inventory stored on this device.',
              ),
              const SizedBox(height: 24),
              const SectionHeader(
                title: 'Hotel stock desk',
                subtitle: 'Identity, currency, and default stock rules.',
              ),
              const SizedBox(height: 12),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(settings.storeName),
                      subtitle: Text(
                        '${settings.currencyCode} (${settings.currencySymbol})  |  '
                        'Low-stock default: ${settings.defaultLowStockThreshold}',
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editStoreSettings(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Appearance',
                subtitle: AppConfig.usesLiveBackend
                    ? 'The hotel display preference is shared across devices.'
                    : 'Choose how DreamStore looks on this device.',
              ),
              const SizedBox(height: 12),
              SectionCard(
                child: SegmentedButton<String>(
                  expandedInsets: EdgeInsets.zero,
                  segments: const [
                    ButtonSegment(
                      value: 'system',
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: 'light',
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: 'dark',
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) async {
                    await _runAction(
                      context,
                      () => controller.updateSettings(
                        settings.copyWith(themeMode: selection.first),
                      ),
                      success: 'Appearance updated',
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Backup & restore',
                subtitle: AppConfig.usesLiveBackend
                    ? 'Back up the shared inventory before replacing live data.'
                    : 'Web data belongs to this browser. Copy a backup regularly.',
              ),
              const SizedBox(height: 12),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.copy_all_outlined),
                      title: const Text('Copy inventory backup'),
                      subtitle: const Text(
                        'Copies products, sales, department usage, and settings',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(text: controller.exportJson()),
                        );
                        if (!context.mounted) return;
                        _showMessage(context, 'Backup copied to clipboard');
                      },
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.restore_page_outlined),
                      title: const Text('Restore from backup'),
                      subtitle: const Text(
                        'Replaces the inventory after confirmation',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _restoreBackup(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Data tools',
                subtitle: AppConfig.usesLiveBackend
                    ? 'Actions here affect the shared hotel inventory on every device.'
                    : 'Actions here affect this browser or device only.',
              ),
              const SizedBox(height: 12),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (AppConfig.allowDemoData && controller.snapshot.isEmpty)
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text('Load starter inventory'),
                        subtitle: const Text(
                          'Adds sample hotel stock for training',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _runAction(
                          context,
                          controller.seedDemoData,
                          success: 'Starter inventory loaded',
                        ),
                      ),
                    if (AppConfig.allowDemoData && controller.snapshot.isEmpty)
                      const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      textColor: Theme.of(context).colorScheme.error,
                      iconColor: Theme.of(context).colorScheme.error,
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: const Text('Clear inventory data'),
                      subtitle: const Text(
                        'Removes stock, sales, issues, and reports',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: controller.snapshot.isEmpty
                          ? null
                          : () => _clearInventory(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionCard(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerLow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_done_outlined),
                        const SizedBox(width: 10),
                        Text(
                          AppConfig.usesLiveBackend
                              ? 'Live database'
                              : 'Build & local data',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AppConfig.usesLiveBackend
                          ? 'Shared MySQL inventory through the hotel API. Refresh to see changes from other devices; internet is required for reads and writes.'
                          : AppConfig.isProduction
                          ? 'Production build. Data is stored in this browser or device. An open web session works offline; reopening needs a connection.'
                          : 'Development build. Starter inventory is available for testing.',
                    ),
                    const SizedBox(height: 6),
                    if (AppConfig.usesLiveBackend) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: controller.isBusy
                            ? null
                            : () => _runAction(
                                context,
                                controller.load,
                                success: 'Latest inventory loaded',
                              ),
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Refresh shared inventory'),
                      ),
                    ],
                    Text(
                      'Environment: ${AppConfig.environment}  |  Support: ${AppConfig.supportLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'DreamStore 1.0.0',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editStoreSettings(BuildContext context) async {
    final settings = controller.settings;
    final nameController = TextEditingController(text: settings.storeName);
    final codeController = TextEditingController(text: settings.currencyCode);
    final symbolController = TextEditingController(
      text: settings.currencySymbol,
    );
    final thresholdController = TextEditingController(
      text: settings.defaultLowStockThreshold.toString(),
    );
    var decimalDigits = settings.currencyDecimalDigits;
    final formKey = GlobalKey<FormState>();

    final updated = await showDialog<StoreSettings>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Stock desk settings'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Business or hotel name',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: codeController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Currency code',
                              hintText: 'TZS',
                            ),
                            validator: _required,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: symbolController,
                            decoration: const InputDecoration(
                              labelText: 'Currency symbol',
                              hintText: 'TSh',
                            ),
                            validator: _required,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: decimalDigits,
                      decoration: const InputDecoration(
                        labelText: 'Currency decimal places',
                      ),
                      items: List.generate(
                        5,
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => decimalDigits = value!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: thresholdController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Default low-stock level',
                      ),
                      validator: (value) => int.tryParse(value ?? '') == null
                          ? 'Enter a whole number'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(
                  dialogContext,
                  settings.copyWith(
                    storeName: nameController.text.trim(),
                    currencyCode: codeController.text.trim().toUpperCase(),
                    currencySymbol: symbolController.text.trim(),
                    currencyDecimalDigits: decimalDigits,
                    defaultLowStockThreshold: int.parse(
                      thresholdController.text,
                    ),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    codeController.dispose();
    symbolController.dispose();
    thresholdController.dispose();
    if (updated == null || !context.mounted) return;
    await _runAction(
      context,
      () => controller.updateSettings(updated),
      success: 'Settings saved',
    );
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final backupController = TextEditingController();
    final encoded = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore inventory backup'),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: backupController,
            minLines: 7,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Backup JSON',
              hintText: 'Paste the copied DreamStore backup here',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, backupController.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    backupController.dispose();
    if (encoded == null || encoded.isEmpty || !context.mounted) return;
    final confirmed = await _confirm(
      context,
      title: 'Replace current inventory?',
      message:
          'This replaces all products, sales, department issues, reports, and settings. Copy a current backup first if needed.',
      confirmLabel: 'Restore backup',
    );
    if (!confirmed || !context.mounted) return;
    await _runAction(
      context,
      () => controller.importJson(encoded),
      success: 'Backup restored successfully',
    );
  }

  Future<void> _clearInventory(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: 'Clear all inventory data?',
      message: AppConfig.usesLiveBackend
          ? 'This removes products, stock history, sales, usage, and reports from the LIVE hotel database for EVERY device. Copy a backup first. The login account is kept.'
          : 'This permanently removes products, stock history, sales, department issues, and reports from this device. The login account is kept.',
      confirmLabel: 'Clear inventory',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _runAction(
      context,
      () => controller.clearData(preserveSettings: true),
      success: 'Inventory data cleared',
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              destructive ? Icons.warning_amber_rounded : Icons.restore,
              color: destructive
                  ? Theme.of(dialogContext).colorScheme.error
                  : null,
            ),
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(
                          dialogContext,
                        ).colorScheme.error,
                      )
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runAction<T>(
    BuildContext context,
    Future<T> Function() action, {
    required String success,
  }) async {
    try {
      await action();
      if (context.mounted) _showMessage(context, success);
    } on InventoryException catch (error) {
      if (context.mounted) _showMessage(context, error.message, error: true);
    }
  }

  void _showMessage(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}
