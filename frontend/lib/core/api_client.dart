/// HTTP client for the tefteri backend with bearer-token auth.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_address.dart';

const _tokenKey = 'session_token';

/// Holds the current bearer token (null when signed out).
///
/// With [persist], the token is also kept on the device. Android ends the
/// process of an app that is in the background, and the next start would
/// otherwise find no token and show the login screen. The web client does not
/// persist it: the browser keeps the server's HttpOnly session cookie.
class TokenStore extends StateNotifier<String?> {
  /// Creates a store holding [initial]. With [persist] it saves every change.
  TokenStore([super.initial, this.persist = false]);

  /// Whether changes are saved on the device.
  final bool persist;

  /// Reads the token that an earlier run saved; null on the web or when none.
  static Future<String?> load() async {
    if (kIsWeb) return null;
    final token = (await SharedPreferences.getInstance()).getString(_tokenKey);
    return (token == null || token.isEmpty) ? null : token;
  }

  /// Stores [token] (null forgets it).
  void set(String? token) {
    state = token;
    if (persist) unawaited(_save(token));
  }

  Future<void> _save(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }
}

/// Provides the token store.
/// `main()` overrides it with a store that holds the saved token and saves
/// changes.
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
