import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockpilot/auth/auth_service.dart';
import 'package:stockpilot/data/inventory_store.dart';
import 'package:stockpilot/models/inventory_models.dart';
import 'package:stockpilot/screens/inventory_screen.dart';
import 'package:stockpilot/screens/home_shell.dart';
import 'package:stockpilot/screens/departments_screen.dart';
import 'package:stockpilot/screens/product_form_screen.dart';
import 'package:stockpilot/screens/reports_screen.dart';
import 'package:stockpilot/screens/stock_actions.dart';
import 'package:stockpilot/state/inventory_controller.dart';
import 'package:stockpilot/theme/app_theme.dart';
import 'package:stockpilot/widgets/stock_date_field.dart';

void main() {
  final today = DateTime(2026, 9, 13, 14, 30);
  final openingDay = DateTime(2026, 9, 4);
  final deliveryDay = DateTime(2026, 9, 11);

  Future<InventoryController> createController() async {
    final controller = InventoryController(
      MemoryInventoryStore(),
      clock: () => today,
    );
    await controller.load();
    return controller;
  }

  ProductDraft kitchenDraft({int quantity = 10}) => ProductDraft(
    name: 'Kitchen Rice',
    sku: 'RICE-KITCHEN',
    department: HotelDepartment.kitchen,
    initialStock: quantity,
    unitCostMinor: 100,
    receivedAt: openingDay,
  );

  Matcher errorCode(String code) => throwsA(
    isA<InventoryException>().having((error) => error.code, 'code', code),
  );

  test(
    'opening and each delivery retain arrival dates and save timestamps',
    () async {
      final controller = await createController();
      final product = await controller.addProduct(kitchenDraft());
      expect(product.createdAt, today);
      expect(product.receivedAt, openingDay);
      expect(controller.movements.single.occurredAt, openingDay);
      expect(controller.movements.single.recordedAt, today);
      expect(controller.movements.single.department, HotelDepartment.kitchen);

      await controller.restockProduct(
        product.id,
        5,
        160,
        receivedAt: deliveryDay,
        note: 'Supplier 11 September',
      );
      expect(controller.productById(product.id)!.quantity, 15);
      expect(controller.productById(product.id)!.unitCostMinor, 120);
      expect(controller.productById(product.id)!.receivedAt, openingDay);
      expect(controller.movements.last.occurredAt, deliveryDay);
      expect(controller.movements.last.recordedAt, today);
      expect(controller.movements.last.department, HotelDepartment.kitchen);

      final restored = await createController();
      await restored.importJson(controller.exportJson());
      expect(restored.products.single.receivedAt, openingDay);
      expect(restored.movements.last.occurredAt, deliveryDay);
      expect(restored.movements.last.recordedAt, today);
      expect(restored.movements.last.department, HotelDepartment.kitchen);
    },
  );

  test(
    'product edits preserve original receipt and historical departments',
    () async {
      final controller = await createController();
      final product = await controller.addProduct(kitchenDraft());
      await controller.updateProduct(
        product.id,
        kitchenDraft().copyWith(
          department: HotelDepartment.restaurant,
          receivedAt: today,
        ),
      );
      expect(controller.products.single.receivedAt, openingDay);
      expect(controller.products.single.department, HotelDepartment.restaurant);
      expect(controller.movements.single.department, HotelDepartment.kitchen);
      await controller.restock(product.id, 2, 100, receivedAt: deliveryDay);
      expect(controller.movements.last.department, HotelDepartment.restaurant);
    },
  );

  test(
    'older backups migrate dates without inventing department history',
    () async {
      final source = await createController();
      await source.addProduct(kitchenDraft());
      final legacy = jsonDecode(source.exportJson()) as Map<String, dynamic>;
      legacy['schemaVersion'] = 2;
      for (final product in legacy['products'] as List) {
        (product as Map).remove('receivedAt');
      }
      for (final movement in legacy['movements'] as List) {
        (movement as Map)
          ..remove('recordedAt')
          ..remove('department');
      }
      final migrated = await createController();
      await migrated.importJson(jsonEncode(legacy));
      expect(
        migrated.snapshot.schemaVersion,
        InventoryData.currentSchemaVersion,
      );
      expect(migrated.products.single.receivedAt, today);
      expect(migrated.movements.single.recordedAt, openingDay);
      expect(migrated.movements.single.department, isNull);
    },
  );

  test(
    'future arrival and usage dates reject without changing inventory',
    () async {
      final controller = await createController();
      final tomorrow = today.add(const Duration(days: 1));
      await expectLater(
        controller.addProduct(kitchenDraft().copyWith(receivedAt: tomorrow)),
        errorCode('future_stock_date'),
      );
      expect(controller.products, isEmpty);
      final product = await controller.addProduct(kitchenDraft());
      await expectLater(
        controller.restockProduct(product.id, 5, 100, receivedAt: tomorrow),
        errorCode('future_stock_date'),
      );
      await expectLater(
        controller.issueStock(
          product.id,
          HotelDepartment.kitchen,
          2,
          usedAt: tomorrow,
        ),
        errorCode('future_stock_date'),
      );
      await expectLater(
        controller.submitDailyReport(day: tomorrow),
        errorCode('future_stock_date'),
      );
      expect(controller.products.single.quantity, 10);
      expect(controller.movements, hasLength(1));
      expect(controller.departmentIssues, isEmpty);
      expect(controller.dailyReports, isEmpty);
    },
  );

  test(
    'department usage is dated, costed, and locked after daily submission',
    () async {
      final controller = await createController();
      final product = await controller.addProduct(kitchenDraft());
      await expectLater(
        controller.issueStock(product.id, HotelDepartment.housekeeping, 2),
        errorCode('department_mismatch'),
      );
      final issue = await controller.issueStock(
        product.id,
        HotelDepartment.kitchen,
        3,
        usedAt: deliveryDay,
        note: 'Lunch',
      );
      expect(issue.issuedAt, deliveryDay);
      expect(issue.valueMinor, 300);
      expect(controller.products.single.quantity, 7);
      expect(controller.movements.last.occurredAt, deliveryDay);
      expect(controller.movements.last.recordedAt, today);
      expect(controller.issuesForDay(deliveryDay), hasLength(1));
      expect(controller.issuesForDay(today), isEmpty);

      final report = await controller.submitDailyReport(day: deliveryDay);
      expect(report.totalUnits, 3);
      expect(report.totalValueMinor, 300);
      await expectLater(
        controller.issueStock(
          product.id,
          HotelDepartment.kitchen,
          1,
          usedAt: deliveryDay,
        ),
        errorCode('daily_report_submitted'),
      );
      expect(controller.products.single.quantity, 7);
      await controller.issueStock(
        product.id,
        HotelDepartment.kitchen,
        1,
        usedAt: today,
      );
      expect(controller.products.single.quantity, 6);
      expect(controller.dailyReports.single.totalUnits, 3);
    },
  );

  test(
    'usage cannot precede first arrival, including backdated zero-stock catalogue',
    () async {
      final controller = await createController();
      final product = await controller.addProduct(
        kitchenDraft(quantity: 0).copyWith(receivedAt: today),
      );
      await controller.restockProduct(
        product.id,
        5,
        100,
        receivedAt: deliveryDay,
      );
      await expectLater(
        controller.issueStock(
          product.id,
          HotelDepartment.kitchen,
          1,
          usedAt: deliveryDay.subtract(const Duration(days: 1)),
        ),
        errorCode('usage_before_stock_arrival'),
      );
      await controller.issueStock(
        product.id,
        HotelDepartment.kitchen,
        1,
        usedAt: deliveryDay,
      );
      expect(controller.products.single.quantity, 4);
    },
  );

  testWidgets('dated entry and receipt sheets fit a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController();
    final product = await controller.addProduct(kitchenDraft());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProductFormScreen(controller: controller, product: product),
      ),
    );
    await tester.pumpAndSettle();
    final dateField = find.byType(StockDateField);
    await tester.scrollUntilVisible(
      dateField,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.widget<StockDateField>(dateField).value, openingDay);
    expect(tester.widget<StockDateField>(dateField).onChanged, isNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showRestockSheet(
                  context,
                  controller: controller,
                  product: product,
                ),
                child: const Text('Receive stock'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Receive stock'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery arrival date'), findsOneWidget);
    expect(find.text('Usual department: Kitchen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory department selection combines with product search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController();
    await controller.addProduct(kitchenDraft());
    await controller.addProduct(
      ProductDraft(
        name: 'Room Towel',
        sku: 'ROOM-TOWEL',
        department: HotelDepartment.housekeeping,
        initialStock: 8,
        receivedAt: openingDay,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: InventoryScreen(
            controller: controller,
            onAddProduct: () {},
            onProductTap: (_) {},
            onRestock: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final kitchenChip = find.byWidgetPredicate(
      (widget) =>
          widget is ChoiceChip &&
          widget.label is Text &&
          (widget.label as Text).data!.startsWith('Kitchen'),
    );
    expect(kitchenChip, findsOneWidget);
    await tester.ensureVisible(kitchenChip);
    await tester.tap(kitchenChip);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Room');
    await tester.pumpAndSettle();
    expect(find.text('Room Towel'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kitchen usage desk reduces only assigned stock on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // This sheet defaults to the device's current day. Keep its controller on
    // the same clock rather than the fixed historical clock of domain tests.
    final controller = InventoryController(MemoryInventoryStore());
    await controller.load();
    await controller.addProduct(kitchenDraft());
    final towel = await controller.addProduct(
      ProductDraft(
        name: 'Room Towel',
        sku: 'ROOM-TOWEL',
        department: HotelDepartment.housekeeping,
        initialStock: 8,
        receivedAt: openingDay,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: DepartmentsScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Record usage'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record usage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.textContaining('Room Towel'), findsNothing);
    await tester.tap(find.text('Kitchen Rice (10 available)').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantity used'),
      '3',
    );
    final save = find.text('Save usage & reduce stock');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(controller.departmentIssues.single.quantity, 3);
    expect(
      controller.departmentIssues.single.department,
      HotelDepartment.kitchen,
    );
    expect(
      controller.activeProducts
          .firstWhere((p) => p.name == 'Kitchen Rice')
          .quantity,
      7,
    );
    expect(controller.productById(towel.id)!.quantity, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports range and department filters show per-product usage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController();
    final rice = await controller.addProduct(kitchenDraft());
    final towel = await controller.addProduct(
      ProductDraft(
        name: 'Room Towel',
        sku: 'ROOM-TOWEL',
        department: HotelDepartment.housekeeping,
        initialStock: 8,
        unitCostMinor: 500,
        receivedAt: openingDay,
      ),
    );
    await controller.issueStock(
      rice.id,
      HotelDepartment.kitchen,
      3,
      usedAt: deliveryDay,
    );
    await controller.issueStock(
      towel.id,
      HotelDepartment.housekeeping,
      2,
      usedAt: deliveryDay,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: ReportsScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<HotelDepartment>),
    );
    await tester.tap(find.byType(DropdownButtonFormField<HotelDepartment>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(UsageProductTile),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    final summary = tester
        .widget<UsageProductTile>(find.byType(UsageProductTile).first)
        .summary;
    expect(summary.issue.department, HotelDepartment.kitchen);
    expect(summary.quantity, 3);
    expect(summary.valueMinor, 300);
    expect(find.text('Room Towel'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('department overview fits enlarged phone text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController();
    await controller.addProduct(kitchenDraft());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(body: DepartmentsScreen(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('All departments overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All departments overview'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Security'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('delivery history is accessible through the app inventory', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController();
    final product = await controller.addProduct(kitchenDraft());
    await controller.restockProduct(
      product.id,
      5,
      160,
      receivedAt: deliveryDay,
      note: 'Supplier delivery',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: HomeShell(
          controller: controller,
          authService: AuthService(),
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Inventory'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kitchen Rice').first);
    await tester.tap(find.text('Kitchen Rice').first);
    await tester.pumpAndSettle();
    expect(find.text('Latest arrival: 11 Sep 2026'), findsOneWidget);
    await tester.tap(find.text('Delivery history (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Supplier delivery'), findsOneWidget);
    expect(find.textContaining('Unit cost:'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  test(
    'usage summaries retain captured costs across deliveries and month boundaries',
    () async {
      final controller = await createController();
      final rice = await controller.addProduct(kitchenDraft());
      await controller.issueStock(
        rice.id,
        HotelDepartment.kitchen,
        2,
        usedAt: deliveryDay,
      );
      await controller.restockProduct(rice.id, 8, 200, receivedAt: deliveryDay);
      await controller.issueStock(
        rice.id,
        HotelDepartment.kitchen,
        3,
        usedAt: today,
      );
      final summary = summarizeUsage(controller.departmentIssues).single;
      expect(summary.quantity, 5);
      expect(summary.valueMinor, 650);
      expect(summary.recordCount, 2);
      final firstSeptember = DateTime(2026, 9, 1);
      expect(
        UsagePeriod.sevenDays.contains(
          DateTime(2026, 8, 26),
          reference: firstSeptember,
        ),
        isTrue,
      );
      expect(
        UsagePeriod.sevenDays.contains(
          DateTime(2026, 8, 25),
          reference: firstSeptember,
        ),
        isFalse,
      );
      expect(
        UsagePeriod.today.contains(
          DateTime(2026, 9, 1, 23, 59),
          reference: firstSeptember,
        ),
        isTrue,
      );
      expect(
        UsagePeriod.all.contains(
          DateTime(2026, 9, 2),
          reference: firstSeptember,
        ),
        isFalse,
      );
    },
  );
}
