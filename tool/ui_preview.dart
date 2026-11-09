import 'package:flutter/material.dart';

import 'package:stockpilot/auth/auth_service.dart';
import 'package:stockpilot/data/inventory_store.dart';
import 'package:stockpilot/models/inventory_models.dart';
import 'package:stockpilot/screens/home_shell.dart';
import 'package:stockpilot/state/inventory_controller.dart';
import 'package:stockpilot/theme/app_theme.dart';

/// Separate visual-verification entry point. Never reads real inventory or
/// creates a persisted account. It is not the production application target.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await createPreviewController();
  runApp(_VisualPreview(controller: controller));
}

Future<InventoryController> createPreviewController({
  DateTime? reference,
}) async {
  final now = reference ?? DateTime.now();
  final controller = InventoryController(
    MemoryInventoryStore(),
    clock: () => now,
  );
  await controller.load();
  final arrived = DateTime(now.year, now.month, now.day - 14, 10, 30);
  final samples = <Product>[];

  Future<Product> add(
    String name,
    String sku,
    HotelDepartment department,
    int quantity,
    int cost,
    int price,
    int threshold,
  ) async {
    final product = await controller.addProduct(
      ProductDraft(
        name: name,
        sku: sku,
        department: department,
        category: department.label,
        initialStock: quantity,
        unitCostMinor: cost,
        salePriceMinor: price,
        lowStockThreshold: threshold,
        receivedAt: arrived,
        description: 'Sample stock for visual verification only.',
      ),
    );
    samples.add(product);
    return product;
  }

  final rice = await add(
    'Basmati rice',
    'KIT-RICE',
    HotelDepartment.kitchen,
    180,
    2800,
    4500,
    20,
  );
  final tomatoes = await add(
    'Fresh tomatoes',
    'KIT-TOM',
    HotelDepartment.kitchen,
    100,
    3200,
    5000,
    15,
  );
  final oil = await add(
    'Sunflower oil',
    'KIT-OIL',
    HotelDepartment.kitchen,
    32,
    7800,
    10000,
    8,
  );
  await add(
    'Free-range eggs',
    'KIT-EGG',
    HotelDepartment.kitchen,
    12,
    500,
    800,
    15,
  );
  await add(
    'Fresh basil',
    'KIT-BASIL',
    HotelDepartment.kitchen,
    0,
    1500,
    2500,
    4,
  );
  final soap = await add(
    'Guest bath soap',
    'HK-SOAP',
    HotelDepartment.housekeeping,
    240,
    600,
    1200,
    40,
  );
  await add(
    'Floor cleaner',
    'HK-FLOOR',
    HotelDepartment.housekeeping,
    9,
    6500,
    9000,
    10,
  );
  final towels = await add(
    'Cotton towels',
    'LAU-TOWEL',
    HotelDepartment.laundry,
    60,
    18000,
    25000,
    10,
  );
  final water = await add(
    'Sparkling water',
    'REST-WATER',
    HotelDepartment.restaurant,
    96,
    2000,
    3500,
    12,
  );
  await add(
    'LED light bulbs',
    'MAIN-LED',
    HotelDepartment.maintenance,
    18,
    4500,
    6500,
    3,
  );
  await add(
    'Guest key cards',
    'REC-KEY',
    HotelDepartment.reception,
    6,
    3000,
    5000,
    8,
  );
  await add(
    'Printing paper',
    'OFF-PAPER',
    HotelDepartment.office,
    24,
    12000,
    15000,
    5,
  );

  final patterns = <Product, List<int>>{
    rice: [4, 8, 6, 10, 5, 12, 9],
    tomatoes: [6, 7, 8, 5, 9, 7, 4],
    oil: [1, 2, 1, 2, 1, 2, 1],
    soap: [8, 10, 6, 12, 8, 10, 4],
    towels: [2, 3, 1, 2, 2, 4, 2],
    water: [1, 2, 3, 4, 1, 3, 2],
  };
  for (var index = 0; index < 7; index++) {
    final date = DateTime(now.year, now.month, now.day - 6 + index, 9, 15);
    for (final entry in patterns.entries) {
      await controller.issueStock(
        entry.key.id,
        entry.key.department,
        entry.value[index],
        usedAt: date,
        note: 'Sample daily consumption.',
      );
    }
  }
  await controller.restockProduct(
    rice.id,
    80,
    3000,
    receivedAt: DateTime(now.year, now.month, now.day - 2, 11, 30),
    note: 'Sample supplier delivery.',
  );
  await controller.recordSale(
    [SaleItemInput(productId: water.id, quantity: 6)],
    customerName: 'Sample guest',
    paymentMethod: 'Cash',
    note: 'Sample transaction only.',
  );
  return controller;
}

class _VisualPreview extends StatelessWidget {
  const _VisualPreview({required this.controller});
  final InventoryController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DreamStore · Sample visual preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      home: Banner(
        message: 'SAMPLE DATA',
        location: BannerLocation.topEnd,
        color: const Color(0xFF956013),
        child: HomeShell(
          controller: controller,
          authService: _PreviewAuthService(),
          onSignOut: () {},
        ),
      ),
    );
  }
}

/// Read-only identity prevents preview profile actions reaching preferences.
class _PreviewAuthService extends AuthService {
  @override
  Future<bool> get hasAccount async => true;

  @override
  Future<String?> get accountName async => 'Sample hotel manager';

  @override
  Future<String?> get accountEmail async => null;

  @override
  Future<bool> login({required String email, required String password}) async =>
      true;

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {}

  @override
  Future<String?> recoverEmail() async => null;

  @override
  Future<void> resetPassword({
    required String name,
    required String email,
    required String newPassword,
  }) async {}

  @override
  Future<void> clearAccount() async {}

  @override
  Future<void> resetAllAccounts() async {}
}
