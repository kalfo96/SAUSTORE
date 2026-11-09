// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stockpilot/auth/auth_service.dart';
import 'package:stockpilot/data/inventory_store.dart';
import 'package:stockpilot/models/inventory_models.dart';
import 'package:stockpilot/screens/auth_screen.dart';
import 'package:stockpilot/state/inventory_controller.dart';
import 'package:stockpilot/theme/app_theme.dart';

void main() {
  test(
    'sales reduce stock and restocking records inventory movements',
    () async {
      final controller = InventoryController(MemoryInventoryStore());
      await controller.load();
      final product = await controller.addProduct(
        const ProductDraft(
          name: 'Test Rice',
          sku: 'TEST-RICE',
          initialStock: 5,
          unitCostMinor: 100,
          salePriceMinor: 150,
        ),
      );

      final sale = await controller.recordSale([
        SaleItemInput(productId: product.id, quantity: 2),
      ]);
      expect(sale.totalUnits, 2);
      expect(controller.productById(product.id)!.quantity, 3);
      expect(controller.movements.last.type, StockMovementType.sale);
      expect(controller.movements.last.quantityDelta, -2);

      await controller.restockProduct(
        product.id,
        4,
        120,
        note: 'Supplier delivery',
      );
      expect(controller.productById(product.id)!.quantity, 7);
      expect(controller.movements.last.type, StockMovementType.restock);
      expect(controller.movements.last.quantityDelta, 4);
    },
  );

  test(
    'department issues reduce central stock and submit daily totals',
    () async {
      final controller = InventoryController(MemoryInventoryStore());
      await controller.load();
      final product = await controller.addProduct(
        const ProductDraft(
          name: 'Kitchen Oil',
          sku: 'KITCHEN-OIL',
          department: HotelDepartment.kitchen,
          initialStock: 12,
          unitCostMinor: 500,
        ),
      );

      final issue = await controller.issueStock(
        product.id,
        HotelDepartment.kitchen,
        3,
        note: 'Breakfast service',
      );
      expect(issue.quantity, 3);
      expect(issue.department, HotelDepartment.kitchen);
      expect(controller.productById(product.id)!.quantity, 9);
      expect(controller.movements.last.type, StockMovementType.departmentIssue);

      final report = await controller.submitDailyReport();
      expect(report.totalUnits, 3);
      expect(report.totalValueMinor, 1500);
      expect(controller.isDailyReportSubmitted(DateTime.now()), isTrue);
    },
  );

  test('overselling is rejected and voiding a sale restores stock', () async {
    final controller = InventoryController(MemoryInventoryStore());
    await controller.load();
    final product = await controller.addProduct(
      const ProductDraft(
        name: 'Guest Water',
        sku: 'WATER-TEST',
        initialStock: 3,
        unitCostMinor: 500,
        salePriceMinor: 800,
      ),
    );

    await expectLater(
      controller.recordSale([
        SaleItemInput(productId: product.id, quantity: 4),
      ]),
      throwsA(isA<InventoryException>()),
    );
    expect(controller.productById(product.id)!.quantity, 3);
    expect(controller.sales, isEmpty);

    final sale = await controller.recordSale([
      SaleItemInput(productId: product.id, quantity: 3),
    ]);
    expect(controller.productById(product.id)!.isOutOfStock, isTrue);

    await controller.voidSale(sale.id, reason: 'Test reversal');
    expect(controller.productById(product.id)!.quantity, 3);
    expect(controller.sales.single.isVoided, isTrue);
    expect(controller.movements.last.type, StockMovementType.reversal);
  });

  test('exported inventory can be restored into a fresh store', () async {
    final source = InventoryController(MemoryInventoryStore());
    await source.load();
    await source.addProduct(
      const ProductDraft(
        name: 'Room Towels',
        sku: 'TOWEL-ROOM',
        department: HotelDepartment.housekeeping,
        initialStock: 20,
        unitCostMinor: 6000,
      ),
    );

    final restored = InventoryController(MemoryInventoryStore());
    await restored.load();
    await restored.importJson(source.exportJson());

    expect(restored.products.single.name, 'Room Towels');
    expect(restored.products.single.quantity, 20);
    expect(restored.movements.single.type, StockMovementType.opening);
  });

  test('local account registration and password reset are persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();

    expect(await auth.hasAccount, isFalse);
    await auth.register(
      name: 'Hotel Admin',
      email: 'ADMIN@SAU.TEST',
      password: 'secret1',
    );

    expect(await auth.hasAccount, isTrue);
    expect(
      await auth.login(email: 'admin@sau.test', password: 'secret1'),
      isTrue,
    );
    expect(
      await auth.login(email: 'admin@sau.test', password: 'wrong'),
      isFalse,
    );

    await auth.resetPassword(
      name: 'hotel admin',
      email: 'admin@sau.test',
      newPassword: 'secret2',
    );
    expect(
      await auth.login(email: 'admin@sau.test', password: 'secret2'),
      isTrue,
    );
  });

  testWidgets('registration screen fits a compact phone viewport', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: AuthScreen(
          authService: AuthService(),
          initialMode: AuthMode.register,
          onAuthenticated: () {},
          onAccountCreated: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DreamStore'), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
