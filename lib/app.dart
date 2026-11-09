import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'config/app_config.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'state/inventory_controller.dart';
import 'theme/app_theme.dart';

class StockPilotApp extends StatelessWidget {
  const StockPilotApp({
    super.key,
    required this.controller,
    required this.authService,
  });

  final InventoryController controller;
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final themeMode = switch (controller.settings.themeMode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: AuthGate(
            authService: authService,
            onSessionReady: authService.isRemote ? controller.load : null,
            onSessionClosed: authService.isRemote
                ? controller.resetSessionView
                : null,
            childBuilder: (onSignOut) => HomeShell(
              controller: controller,
              authService: authService,
              onSignOut: onSignOut,
            ),
          ),
        );
      },
    );
  }
}
