/// Sign-in state and actions.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Whether the user is signed in, plus the last error message.
@immutable
class AuthState {
  /// Creates a state.
  const AuthState({
    this.signedIn = false,
    this.error,
    this.isAdmin = false,
    this.restoring = false,
  });

  /// True after a successful login.
  final bool signedIn;

  /// True while the app checks for a session from an earlier visit.
  final bool restoring;

  /// True when the signed-in user is an administrator.
  final bool isAdmin;

  /// Human-readable error from the last attempt, if any.
  final String? error;
}

/// Controller for login and logout.
class AuthController extends StateNotifier<AuthState> {
  /// Creates a controller using [_ref] for the API client.
  AuthController(this._ref) : super(const AuthState());

  final Ref _ref;

  /// Signs in with [username] and [password].
  Future<void> login(String username, String password) async {
    try {
      final r = await _ref.read(dioProvider).post<Map<String, dynamic>>(
        '/auth/login',
        data: {'username': username, 'password': password},
      );
      _ref.read(tokenStoreProvider.notifier).set(r.data!['token'] as String);
      state = AuthState(signedIn: true, isAdmin: await _loadIsAdmin());
    } on DioException catch (e) {
      final detail = (e.response?.data is Map)
          ? (e.response!.data as Map)['detail']?.toString()
          : null;
      state = AuthState(error: detail ?? 'Cannot reach the server');
    }
  }

  /// Resumes an earlier session. On the web the server's HttpOnly session
  /// cookie survives a page reload; the other clients send the token that
  /// they saved on the device. When the server accepts the session, the user
  /// stays signed in.
  ///
  /// When the server refuses it (it expired), the saved token is dropped and
  /// the user signs in again. When the server cannot be reached, a saved token
  /// is kept and the user stays signed in: coming back to the app on a bad
  /// connection must not sign anyone out. The screens then show their own
  /// "cannot reach the server" message, with a way to try again.
  Future<void> restore() async {
    final saved = _ref.read(tokenStoreProvider);
    state = const AuthState(restoring: true);
    try {
      final r =
          await _ref.read(dioProvider).get<Map<String, dynamic>>('/auth/me');
      state = AuthState(signedIn: true, isAdmin: r.data?['is_admin'] == true);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final refused = status == 401 || status == 403;
      if (saved != null && !refused) {
        state = const AuthState(signedIn: true);
        return;
      }
      if (refused) _ref.read(tokenStoreProvider.notifier).set(null);
      state = const AuthState();
    }
  }

  /// Reads the current user; a failure counts as "not an administrator".
  Future<bool> _loadIsAdmin() async {
    try {
      final r =
          await _ref.read(dioProvider).get<Map<String, dynamic>>('/auth/me');
      return r.data?['is_admin'] == true;
    } on DioException {
      return false;
    }
  }

  /// Signs out and forgets the token.
  Future<void> logout() async {
    try {
      await _ref.read(dioProvider).post<void>('/auth/logout');
    } on DioException {
      // Token is dropped locally regardless.
    }
    _ref.read(tokenStoreProvider.notifier).set(null);
    state = const AuthState();
  }
}

/// Provides the auth controller.
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>(AuthController.new);
