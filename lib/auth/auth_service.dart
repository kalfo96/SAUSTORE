import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/live_api_client.dart';

class AuthService {
  AuthService({SharedPreferences? preferences, LiveApiClient? apiClient})
    : _preferences = preferences,
      _apiClient = apiClient;

  final LiveApiClient? _apiClient;

  LiveApiClient? get apiClient => _apiClient;

  bool get isRemote => apiClient != null;

  static const _managedAccountMessage =
      'Live accounts are managed by your hotel administrator. Contact them to create, reset, or remove an account.';

  static const _emailKey = 'dream_sau.auth.email';
  static const _nameKey = 'dream_sau.auth.name';
  static const _passwordKey = 'dream_sau.auth.password_hash';

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<bool> get hasAccount async {
    if (isRemote) return true;
    final preferences = await _prefs();
    return preferences.getString(_emailKey)?.isNotEmpty == true &&
        preferences.getString(_passwordKey)?.isNotEmpty == true;
  }

  Future<String?> get accountName async {
    if (isRemote) return apiClient!.user?.name;
    final preferences = await _prefs();
    return preferences.getString(_nameKey);
  }

  Future<String?> get accountEmail async {
    if (isRemote) return apiClient!.user?.email;
    final preferences = await _prefs();
    return preferences.getString(_emailKey);
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    if (isRemote) throw const AuthException(_managedAccountMessage);
    if (await hasAccount) {
      throw const AuthException('An account already exists on this device.');
    }
    final preferences = await _prefs();
    await preferences.setString(_nameKey, name.trim());
    await preferences.setString(_emailKey, email.trim().toLowerCase());
    await preferences.setString(_passwordKey, _hash(password));
  }

  Future<bool> login({required String email, required String password}) async {
    if (isRemote) {
      try {
        await apiClient!.login(email: email, password: password);
        return true;
      } on LiveApiException catch (error) {
        if (error.code == 'invalid_credentials') return false;
        throw AuthException(error.message);
      }
    }
    final preferences = await _prefs();
    return preferences.getString(_emailKey) == email.trim().toLowerCase() &&
        preferences.getString(_passwordKey) == _hash(password);
  }

  Future<String?> recoverEmail() async {
    if (isRemote) return null;
    final preferences = await _prefs();
    return preferences.getString(_emailKey);
  }

  Future<void> resetPassword({
    required String name,
    required String email,
    required String newPassword,
  }) async {
    if (isRemote) throw const AuthException(_managedAccountMessage);
    final preferences = await _prefs();
    final savedName = preferences.getString(_nameKey)?.trim().toLowerCase();
    final savedEmail = preferences.getString(_emailKey)?.trim().toLowerCase();
    if (savedName == null ||
        savedEmail == null ||
        savedName != name.trim().toLowerCase() ||
        savedEmail != email.trim().toLowerCase()) {
      throw const AuthException(
        'The name and email do not match this device account.',
      );
    }
    await preferences.setString(_passwordKey, _hash(newPassword));
  }

  Future<void> clearAccount() async {
    if (isRemote) throw const AuthException(_managedAccountMessage);
    final preferences = await _prefs();
    await preferences.remove(_emailKey);
    await preferences.remove(_nameKey);
    await preferences.remove(_passwordKey);
  }

  Future<void> resetAllAccounts() => clearAccount();

  Future<void> signOut() async {
    if (!isRemote) return;
    try {
      await apiClient!.logout();
    } on LiveApiException {
      // Signing out must succeed locally even when the server is unreachable.
    } finally {
      apiClient!.clearSession();
    }
  }

  String _hash(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}
