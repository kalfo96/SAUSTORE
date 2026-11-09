/// Compile-time configuration for local, staging, and production builds.
/// Values are supplied with `--dart-define` or `--dart-define-from-file`.
/// No secrets belong here: every Flutter web define is visible in the bundle.
abstract final class AppConfig {
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: bool.fromEnvironment('dart.vm.product')
        ? 'production'
        : 'development',
  );

  static const appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'DreamStore',
  );

  static const supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: '',
  );

  /// Public server URL only. Database credentials must stay on the server.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dreamstore.sauinndream.com/api/',
  );

  static bool get usesLiveBackend => apiBaseUrl.trim().isNotEmpty;

  static const _demoSetting = String.fromEnvironment(
    'ENABLE_DEMO_DATA',
    defaultValue: '',
  );

  static bool get isProduction => environment == 'production';

  static String get supportLabel =>
      supportEmail.isEmpty ? 'Hotel administrator' : supportEmail;

  static bool get allowDemoData {
    if (usesLiveBackend) return false;
    if (_demoSetting.isEmpty) return !isProduction;
    return _demoSetting.toLowerCase() == 'true';
  }
}
