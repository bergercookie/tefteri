/// HTTP client for the tefteri backend with bearer-token auth.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server_address.dart';

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
    baseUrl: ref.watch(apiBaseUrlProvider),
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
