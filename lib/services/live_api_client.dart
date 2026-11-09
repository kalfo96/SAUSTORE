import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LiveApiException implements Exception {
  const LiveApiException(this.message, {this.code = 'request_failed'});

  final String message;
  final String code;

  @override
  String toString() => message;
}

class LiveUser {
  const LiveUser({required this.name, required this.email});
  final String name;
  final String email;
}

/// Authenticated JSON transport. Session credentials stay only in memory.
class LiveApiClient extends ChangeNotifier {
  LiveApiClient({
    required String baseUrl,
    bool allowInsecureHttp = false,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : baseUri = _validateBaseUri(baseUrl, allowInsecureHttp),
       _client = client ?? http.Client();

  final Uri baseUri;
  final http.Client _client;
  final Duration requestTimeout;
  String? _token;
  LiveUser? _user;
  int _sessionGeneration = 0;

  LiveUser? get user => _user;
  bool get isAuthenticated => _token != null;

  static Uri _validateBaseUri(String value, bool allowInsecureHttp) {
    var uri = Uri.tryParse(value.trim());
    if (uri != null && kIsWeb && value.trim().startsWith('/')) {
      uri = Uri.base.resolveUri(uri);
    }
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(uri.scheme == 'https' ||
            (allowInsecureHttp &&
                uri.scheme == 'http' &&
                const ['localhost', '127.0.0.1', '::1'].contains(uri.host)))) {
      throw const LiveApiException(
        'The live API address is invalid. Configure an HTTPS address.',
        code: 'invalid_api_url',
      );
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  Future<void> login({required String email, required String password}) async {
    clearSession();
    final generation = _sessionGeneration;
    final response = await _request(
      'POST',
      'auth/login',
      authenticated: false,
      body: {'email': email.trim().toLowerCase(), 'password': password},
    );
    final token = response['token'];
    final account = response['user'];
    if (token is! String ||
        token.isEmpty ||
        account is! Map<String, dynamic> ||
        account['name'] is! String ||
        account['email'] is! String) {
      throw const LiveApiException(
        'The server returned an invalid login response.',
        code: 'invalid_response',
      );
    }
    if (generation != _sessionGeneration) {
      throw const LiveApiException(
        'Please sign in again.',
        code: 'session_expired',
      );
    }
    _token = token;
    _user = LiveUser(
      name: account['name'] as String,
      email: account['email'] as String,
    );
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      if (isAuthenticated) await _request('POST', 'auth/logout');
    } finally {
      clearSession();
    }
  }

  void clearSession() {
    _sessionGeneration++;
    _token = null;
    _user = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> getInventory() => _request('GET', 'inventory');

  Future<Map<String, dynamic>> putInventory({
    required int expectedVersion,
    required Map<String, dynamic> data,
  }) => _request(
    'PUT',
    'inventory',
    body: {'expectedVersion': expectedVersion, 'data': data},
  );

  Future<Map<String, dynamic>> deleteInventory({
    required int expectedVersion,
  }) => _request(
    'DELETE',
    'inventory',
    body: {'expectedVersion': expectedVersion},
  );

  Future<Map<String, dynamic>> _request(
    String method,
    String route, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    if (authenticated && !isAuthenticated) {
      throw const LiveApiException(
        'Please sign in again.',
        code: 'session_expired',
      );
    }
    final generation = _sessionGeneration;
    final request = http.Request(method, baseUri.resolve(route))
      ..followRedirects = false
      ..headers['accept'] = 'application/json';
    if (authenticated) request.headers['authorization'] = 'Bearer $_token';
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout);
      if (generation != _sessionGeneration) {
        throw const LiveApiException(
          'Please sign in again.',
          code: 'session_expired',
        );
      }
      if (response.statusCode == 401 && authenticated) clearSession();
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final code = error is Map && error['code'] is String
            ? error['code'] as String
            : 'request_failed';
        throw LiveApiException(_errorMessage(code), code: code);
      }
      return decoded;
    } on TimeoutException {
      throw const LiveApiException(
        'The request timed out. Refresh the live inventory before trying again.',
        code: 'request_timeout',
      );
    } on http.ClientException {
      throw const LiveApiException(
        'The server could not be reached. Check your connection and try again.',
        code: 'network_error',
      );
    } on FormatException {
      throw const LiveApiException(
        'The server returned an invalid response.',
        code: 'invalid_response',
      );
    }
  }

  static String _errorMessage(String code) => switch (code) {
    'invalid_credentials' => 'The email or password is incorrect.',
    'session_expired' => 'Your session has expired. Please sign in again.',
    'inventory_conflict' =>
      'Stock changed on another device. Refresh and try again.',
    'rate_limited' => 'Too many requests. Please wait before trying again.',
    _ =>
      'The server could not complete the request. Please try again or contact your administrator.',
  };

  @override
  void dispose() {
    _sessionGeneration++;
    _token = null;
    _user = null;
    _client.close();
    super.dispose();
  }
}
