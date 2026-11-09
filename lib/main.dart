import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'auth/auth_service.dart';
import 'data/inventory_store.dart';
import 'state/inventory_controller.dart';
import 'data/remote_inventory_store.dart';
import 'services/live_api_client.dart';
import 'config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    final apiClient = AppConfig.usesLiveBackend
        ? LiveApiClient(
            baseUrl: AppConfig.apiBaseUrl,
            allowInsecureHttp: !AppConfig.isProduction,
          )
        : null;
    final controller = InventoryController(
      apiClient == null
          ? SharedPreferencesInventoryStore()
          : RemoteInventoryStore(apiClient: apiClient),
    );
    if (apiClient == null) {
      try {
        await controller.load();
      } catch (_) {
        // Local storage errors are shown by the inventory recovery UI.
      }
    }
    runApp(
      StockPilotApp(
        controller: controller,
        authService: AuthService(apiClient: apiClient),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'The live API address is not configured correctly. Use an HTTPS address for mobile builds, or /api/ on the hosted web app.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
