/// HTTP client for the tefteri backend with bearer-token auth.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _apiOverride = String.fromEnvironment('TEFTERI_API');

/// Base URL of the backend API; override at build time with
/// `--dart-define=TEFTERI_API=https://host/api/v1`. The web client defaults to
/// the server it was loaded from, the other clients to `localhost:8000`.
final apiBaseUrl = _apiOverride.isNotEmpty
    ? _apiOverride
    : kIsWeb
        ? Uri.base.resolve('api/v1').toString()
        : 'http://localhost:8000/api/v1';

/// Holds the current bearer token (null when signed out).
class TokenStore extends StateNotifier<String?> {
  /// Creates an empty store.
  TokenStore() : super(null);

  /// Stores [token].
  void set(String? token) => state = token;
}

/// Provides the token store.
final tokenStoreProvider =
    StateNotifierProvider<TokenStore, String?>((_) => TokenStore());

/// Provides a Dio instance that adds the bearer token to every request.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: apiBaseUrl,
    // Lets the server accept the web client's session cookie on requests
    // that change data; other sites cannot send this header (CSRF guard).
    headers: {'X-Tefteri-Client': 'tefteri'},
  ));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final token = ref.read(tokenStoreProvider);
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }));
  return dio;
});
