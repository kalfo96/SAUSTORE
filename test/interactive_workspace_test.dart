import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockpilot/app.dart';
import 'package:stockpilot/auth/auth_service.dart';
import 'package:stockpilot/data/inventory_store.dart';
import 'package:stockpilot/data/remote_inventory_store.dart';
import 'package:stockpilot/models/inventory_models.dart';
import 'package:stockpilot/screens/dashboard_screen.dart';
import 'package:stockpilot/screens/departments_screen.dart';
import 'package:stockpilot/screens/home_shell.dart';
import 'package:stockpilot/screens/inventory_screen.dart';
import 'package:stockpilot/services/live_api_client.dart';
import 'package:stockpilot/state/inventory_controller.dart';
import 'package:stockpilot/theme/app_theme.dart';

Future<InventoryController> fixture() async {
  final controller = InventoryController(MemoryInventoryStore());
  await controller.load();
  final now = DateTime.now();
  final arrival = now.subtract(const Duration(days: 10));
  final rice = await controller.addProduct(
    ProductDraft(
      name: 'Kitchen Rice',
      sku: 'KITCHEN-RICE',
      initialStock: 20,
      unitCostMinor: 100,
      receivedAt: arrival,
    ),
  );
  final towel = await controller.addProduct(
    ProductDraft(
      name: 'Room Towel',
      sku: 'ROOM-TOWEL',
      department: HotelDepartment.housekeeping,
      initialStock: 20,
      unitCostMinor: 500,
      receivedAt: arrival,
    ),
  );
  await controller.issueStock(
    rice.id,
    HotelDepartment.kitchen,
    2,
    usedAt: now.subtract(const Duration(days: 1)),
  );
  await controller.issueStock(
    towel.id,
    HotelDepartment.housekeeping,
    3,
    usedAt: now.subtract(const Duration(days: 1)),
  );
  await controller.issueStock(rice.id, HotelDepartment.kitchen, 1);
  return controller;
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('usage chart selects a real day and filters the department', (
    tester,
  ) async {
    phone(tester);
    final controller = await fixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: DashboardScreen(
            controller: controller,
            onAddProduct: () {},
            onOpenInventory: () {},
            onOpenSale: () {},
            onOpenProduct: (_) {},
            onOpenDepartment: (_) {},
            onOpenReports: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final yesterday = find.byKey(const ValueKey('dashboard-usage-day-5'));
    await tester.ensureVisible(yesterday);
    await tester.pumpAndSettle();
    await tester.tap(yesterday);
    await tester.pumpAndSettle();
    final caption = find.byKey(const ValueKey('dashboard-selected-usage'));
    expect(
      find.descendant(
        of: caption,
        matching: find.textContaining('5 units used'),
      ),
      findsOneWidget,
    );
    final departments = find.byKey(
      const ValueKey('dashboard-usage-department'),
    );
    await tester.ensureVisible(departments);
    await tester.pumpAndSettle();
    await tester.tap(departments);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: caption,
        matching: find.textContaining('2 units used'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile tabs, quick deliveries, and More navigation work', (
    tester,
  ) async {
    phone(tester);
    SharedPreferences.setMockInitialValues({});
    final controller = await fixture();
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
    final nav = find.byType(NavigationBar);
    await tester.tap(
      find.descendant(of: nav, matching: find.text('Inventory')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InventoryScreen).hitTestable(), findsOneWidget);
    final search = find
        .descendant(
          of: find.byType(InventoryScreen),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(search, 'Rice');
    await tester.tap(find.descendant(of: nav, matching: find.text('Teams')));
    await tester.pumpAndSettle();
    expect(find.byType(DepartmentsScreen).hitTestable(), findsOneWidget);
    await tester.tap(
      find.descendant(of: nav, matching: find.text('Inventory')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, 'Rice');
    await tester.tap(find.byTooltip('Open quick actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receive delivery'));
    await tester.pumpAndSettle();
    expect(find.text('Which stock item has arrived?'), findsOneWidget);
    await tester.tap(find.text('Kitchen Rice').last);
    await tester.pumpAndSettle();
    expect(find.text('Delivery arrival date'), findsOneWidget);
    Navigator.of(tester.element(find.text('Delivery arrival date'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: nav, matching: find.text('More')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(
      find.text('Every sale, delivery, and correction in one timeline.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark dashboard and navigation fit enlarged phone text', (
    tester,
  ) async {
    phone(tester);
    SharedPreferences.setMockInitialValues({});
    final controller = await fixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.8),
            disableAnimations: true,
          ),
          child: child!,
        ),
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
        of: find.byType(NavigationBar),
        matching: find.text('Teams'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DepartmentsScreen).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'two devices cannot overwrite stock and failed action is never replayed',
    () async {
      final original = await fixture();
      var data = original.snapshot.toJson();
      var version = 1;
      var puts = 0;
      final transport = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'token': 'test-session',
              'user': {'name': 'Admin', 'email': 'admin@sau.test'},
            }),
            200,
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({'version': version, 'data': data}),
            200,
          );
        }
        puts++;
        final body = jsonDecode(request.body) as Map;
        if (body['expectedVersion'] != version) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'inventory_conflict',
                'message': 'Stock changed',
              },
            }),
            409,
          );
        }
        data = Map<String, dynamic>.from(body['data'] as Map);
        version++;
        return http.Response(jsonEncode({'version': version}), 200);
      });
      Future<InventoryController> device() async {
        final api = LiveApiClient(
          baseUrl: 'https://stock.sau.test/api/',
          client: transport,
        );
        await api.login(email: 'admin@sau.test', password: 'secret-password');
        final controller = InventoryController(
          RemoteInventoryStore(apiClient: api),
        );
        await controller.load();
        return controller;
      }

      final first = await device();
      final second = await device();
      final id = first.products.first.id;
      await first.issueStock(id, HotelDepartment.kitchen, 2);
      await expectLater(
        second.issueStock(id, HotelDepartment.kitchen, 3),
        throwsA(
          isA<InventoryException>().having(
            (e) => e.code,
            'code',
            'inventory_conflict',
          ),
        ),
      );
      expect(puts, 2);
      expect(second.productById(id)!.quantity, first.productById(id)!.quantity);
      expect(second.departmentIssues, hasLength(first.departmentIssues.length));
      await second.resetSessionView();
      expect(second.snapshot.isEmpty, isTrue);
      expect(data['products'], isNotEmpty);
    },
  );

  testWidgets(
    'live login loads server inventory and session expiry hides workspace',
    (tester) async {
      final stock = await fixture();
      final transport = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'token': 'test-session',
              'user': {'name': 'Hotel Admin', 'email': 'admin@sau.test'},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'version': 1, 'data': stock.snapshot.toJson()}),
          200,
        );
      });
      final api = LiveApiClient(
        baseUrl: 'https://stock.sau.test/api/',
        client: transport,
      );
      final controller = InventoryController(
        RemoteInventoryStore(apiClient: api),
      );
      await tester.pumpWidget(
        StockPilotApp(
          controller: controller,
          authService: AuthService(apiClient: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Register'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'admin@sau.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'secret-password',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Log in'));
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(controller.products, hasLength(2));
      api.clearSession();
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsNothing);
      expect(controller.snapshot.isEmpty, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
