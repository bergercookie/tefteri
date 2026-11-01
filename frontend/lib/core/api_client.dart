/// HTTP client for the tefteri backend with bearer-token auth.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Base URL of the backend API; override at build time with
/// `--dart-define=TEFTERI_API=https://host/api/v1`.
const apiBaseUrl = String.fromEnvironment('TEFTERI_API',
    defaultValue: 'http://localhost:8000/api/v1');

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
  final dio = Dio(BaseOptions(baseUrl: apiBaseUrl));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final token = ref.read(tokenStoreProvider);
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }));
  return dio;
});
