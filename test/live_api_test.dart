import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockpilot/auth/auth_service.dart';
import 'package:stockpilot/data/inventory_store.dart';
import 'package:stockpilot/data/remote_inventory_store.dart';
import 'package:stockpilot/models/inventory_models.dart';
import 'package:stockpilot/services/live_api_client.dart';
import 'package:stockpilot/state/inventory_controller.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _loginResponse() => _json({
  'token': 'memory-only-session-token',
  'user': {'name': 'Hotel Administrator', 'email': 'admin@example.com'},
});

http.Response _error(String code, [int status = 409]) => _json({
  'error': {'code': code, 'message': 'Server internals must not be displayed.'},
}, status);

Matcher _inventoryError(String code) =>
    isA<InventoryException>().having((error) => error.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'live URL is normalized and insecure or secret-bearing URLs are refused',
    () {
      final client = LiveApiClient(baseUrl: 'https://hotel.example/api');
      expect(client.baseUri.toString(), 'https://hotel.example/api/');
      client.dispose();
      for (final url in [
        'http://hotel.example/api/',
        'https://user:password@hotel.example/api/',
        'https://hotel.example/api/?secret=value',
        '/api/',
      ]) {
        expect(
          () => LiveApiClient(baseUrl: url, allowInsecureHttp: true),
          throwsA(isA<LiveApiException>()),
        );
      }
      expect(
        () => LiveApiClient(baseUrl: 'http://localhost:8000/api/'),
        throwsA(isA<LiveApiException>()),
      );
      final local = LiveApiClient(
        baseUrl: 'http://localhost:8000/api/',
        allowInsecureHttp: true,
      );
      local.dispose();
    },
  );

  test(
    'live login uses HTTPS JSON and never persists credentials or token',
    () async {
      SharedPreferences.setMockInitialValues({'local-data': 'untouched'});
      final preferences = await SharedPreferences.getInstance();
      final api = LiveApiClient(
        baseUrl: 'https://hotel.example/api',
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://hotel.example/api/auth/login',
          );
          expect(request.method, 'POST');
          expect(request.headers['content-type'], contains('application/json'));
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(jsonDecode(request.body), {
            'email': 'admin@example.com',
            'password': 'secure-password',
          });
          return _loginResponse();
        }),
      );
      addTearDown(api.dispose);
      final auth = AuthService(preferences: preferences, apiClient: api);
      expect(auth.isRemote, isTrue);
      expect(await auth.hasAccount, isTrue);
      expect(await auth.accountName, isNull);
      expect(
        await auth.login(
          email: ' Admin@Example.com ',
          password: 'secure-password',
        ),
        isTrue,
      );
      expect(api.isAuthenticated, isTrue);
      expect(await auth.accountName, 'Hotel Administrator');
      expect(await auth.accountEmail, 'admin@example.com');
      expect(preferences.getKeys(), {'local-data'});
      expect(preferences.getString('local-data'), 'untouched');
    },
  );

  test(
    'live account recovery, registration and reset remain administrator-managed',
    () async {
      final api = LiveApiClient(baseUrl: 'https://hotel.example/api/');
      addTearDown(api.dispose);
      final auth = AuthService(apiClient: api);
      expect(await auth.hasAccount, isTrue);
      expect(await auth.recoverEmail(), isNull);
      expect(
        auth.register(
          name: 'Someone',
          email: 'someone@example.com',
          password: 'password',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(
        auth.resetPassword(
          name: 'Someone',
          email: 'someone@example.com',
          newPassword: 'password',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(auth.clearAccount(), throwsA(isA<AuthException>()));
      expect(auth.resetAllAccounts(), throwsA(isA<AuthException>()));
    },
  );

  test(
    'incorrect credentials return false without leaving a live session',
    () async {
      final api = LiveApiClient(
        baseUrl: 'https://hotel.example/api/',
        client: MockClient((_) async => _error('invalid_credentials', 401)),
      );
      addTearDown(api.dispose);
      final auth = AuthService(apiClient: api);
      expect(
        await auth.login(email: 'admin@example.com', password: 'incorrect'),
        isFalse,
      );
      expect(api.isAuthenticated, isFalse);
      expect(api.user, isNull);
    },
  );

  test(
    'expired session clears the token and invalidates the loaded inventory version',
    () async {
      var getCount = 0;
      final api = LiveApiClient(
        baseUrl: 'https://hotel.example/api/',
        client: MockClient((request) async {
          if (request.url.path.endsWith('auth/login')) return _loginResponse();
          expect(
            request.headers['authorization'],
            'Bearer memory-only-session-token',
          );
          if (++getCount == 1) return _json({'version': 3, 'data': null});
          return _error('session_expired', 401);
        }),
      );
      addTearDown(api.dispose);
      await api.login(email: 'admin@example.com', password: 'password');
      final store = RemoteInventoryStore(apiClient: api);
      addTearDown(store.dispose);
      await store.load();
      expect(store.version, 3);
      await expectLater(
        store.load(),
        throwsA(_inventoryError('session_expired')),
      );
      expect(api.isAuthenticated, isFalse);
      expect(api.user, isNull);
      expect(store.hasLoaded, isFalse);
    },
  );

  test(
    'login timeout is a friendly error, not a fallback to a local account',
    () async {
      final pending = Completer<http.Response>();
      final api = LiveApiClient(
        baseUrl: 'https://hotel.example/api/',
        requestTimeout: const Duration(milliseconds: 5),
        client: MockClient((_) => pending.future),
      );
      addTearDown(api.dispose);
      final auth = AuthService(apiClient: api);
      await expectLater(
        auth.login(email: 'admin@example.com', password: 'password'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(api.isAuthenticated, isFalse);
      pending.complete(_loginResponse());
      await Future<void>.delayed(Duration.zero);
      expect(api.isAuthenticated, isFalse);
    },
  );

  test(
    'version conflict never retries or overwrites a newer server inventory',
    () async {
      var serverVersion = 4;
      var writes = 0;
      final expectedVersions = <int>[];
      final api = LiveApiClient(
        baseUrl: 'https://hotel.example/api/',
        client: MockClient((request) async {
          if (request.url.path.endsWith('auth/login')) return _loginResponse();
          if (request.method == 'GET') {
            return _json({'version': serverVersion, 'data': null});
          }
          writes++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expectedVersions.add(body['expectedVersion'] as int);
          if (body['expectedVersion'] != serverVersion) {
            return _error('inventory_conflict');
          }
          return _json({'version': ++serverVersion});
        }),
      );
      addTearDown(api.dispose);
      await api.login(email: 'admin@example.com', password: 'password');
      final store = RemoteInventoryStore(apiClient: api);
      addTearDown(store.dispose);
      await store.load();
      serverVersion = 5; // Another device saved after our read.
      await expectLater(
        store.save(InventoryData.empty()),
        throwsA(_inventoryError('inventory_conflict')),
      );
      expect(writes, 1);
      expect(serverVersion, 5);
      expect(store.version, 4);
      await store.load();
      await store.save(InventoryData.empty());
      expect(expectedVersions, [4, 5]);
      expect(store.version, 6);
    },
  );

  test(
    'new live database loads empty and first save sends schema 4 with version zero',
    () async {
      final api = LiveApiClient(
        baseUrl: 'https://hotel.example/api/',
        client: MockClient((request) async {
          if (request.url.path.endsWith('auth/login')) return _loginResponse();
          if (request.method == 'GET') {
            return _json({'version': 0, 'data': null});
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.method, 'PUT');
          expect(body['expectedVersion'], 0);
          expect(body['data']['schemaVersion'], 4);
          expect(body['data']['products'], isEmpty);
          expect(body['data']['requisitions'], isEmpty);
          return _json({'version': 1});
        }),
      );
      addTearDown(api.dispose);
      await api.login(email: 'admin@example.com', password: 'password');
      final store = RemoteInventoryStore(apiClient: api);
      addTearDown(store.dispose);
      expect(await store.load(), isNull);
      await store.save(InventoryData.empty());
      expect(store.version, 1);
    },
  );

  test(
    'live JSON preserves arrival dates, department allocation and kitchen usage',
    () async {
      final date = DateTime(2026, 9, 13, 10);
      final local = InventoryController(
        MemoryInventoryStore(),
        clock: () => date,
      );
      await local.load();
      final product = await local.addProduct(
        ProductDraft(
          name: 'Kitchen rice',
          sku: 'KITCHEN-RICE',
          initialStock: 20,
          unitCostMinor: 10000,
          department: HotelDepartment.kitchen,
          receivedAt: DateTime(2026, 9, 10),
        ),
      );
      await local.issueStock(
        product.id,
        HotelDepartment.kitchen,
        3,
        usedAt: DateTime(2026, 9, 12),
      );
      final api = LiveApiClient(
        baseUrl: 'https://hotel.example/api/',
        client: MockClient((request) async {
          if (request.url.path.endsWith('auth/login')) return _loginResponse();
          return _json({'version': 7, 'data': local.snapshot.toJson()});
        }),
      );
      addTearDown(api.dispose);
      await api.login(email: 'admin@example.com', password: 'password');
      final store = RemoteInventoryStore(apiClient: api);
      addTearDown(store.dispose);
      final loaded = (await store.load())!;
      expect(loaded.products.single.receivedAt, DateTime(2026, 9, 10));
      expect(loaded.products.single.department, HotelDepartment.kitchen);
      expect(loaded.products.single.quantity, 17);
      expect(loaded.departmentIssues.single.quantity, 3);
      expect(loaded.departmentIssues.single.issuedAt, DateTime(2026, 9, 12));
      expect(loaded.movements.last.department, HotelDepartment.kitchen);
      expect(loaded.movements.last.recordedAt, date);
      expect(store.version, 7);
    },
  );

  test(
    'writes and clear require loading and clear uses the accepted server version',
    () async {
      var inventoryRequests = 0;
      final api = LiveApiClient(
        baseUrl: 'https://hotel.example/api/',
        client: MockClient((request) async {
          if (request.url.path.endsWith('auth/login')) return _loginResponse();
          inventoryRequests++;
          if (request.method == 'GET') {
            return _json({'version': 8, 'data': null});
          }
          expect(request.method, 'DELETE');
          expect(jsonDecode(request.body), {'expectedVersion': 8});
          return _json({'version': 9});
        }),
      );
      addTearDown(api.dispose);
      await api.login(email: 'admin@example.com', password: 'password');
      final store = RemoteInventoryStore(apiClient: api);
      addTearDown(store.dispose);
      await expectLater(
        store.save(InventoryData.empty()),
        throwsA(_inventoryError('inventory_not_loaded')),
      );
      await expectLater(
        store.clear(),
        throwsA(_inventoryError('inventory_not_loaded')),
      );
      expect(inventoryRequests, 0);
      await store.load();
      await store.clear();
      expect(store.version, 9);
      expect(inventoryRequests, 2);
    },
  );

  test(
    'sign out clears in-memory credentials even if the server is offline',
    () async {
      var sessionNotifications = 0;
      final api = LiveApiClient(
        baseUrl: 'https://hotel.example/api/',
        client: MockClient((request) async {
          if (request.url.path.endsWith('auth/login')) return _loginResponse();
          expect(request.url.path.endsWith('auth/logout'), isTrue);
          throw http.ClientException('Sensitive internal diagnostic');
        }),
      );
      addTearDown(api.dispose);
      api.addListener(() => sessionNotifications++);
      final auth = AuthService(apiClient: api);
      await auth.login(email: 'admin@example.com', password: 'password');
      final store = RemoteInventoryStore(apiClient: api);
      addTearDown(store.dispose);
      await auth.signOut();
      expect(api.isAuthenticated, isFalse);
      expect(api.user, isNull);
      expect(store.hasLoaded, isFalse);
      expect(sessionNotifications, greaterThanOrEqualTo(3));
    },
  );
}
