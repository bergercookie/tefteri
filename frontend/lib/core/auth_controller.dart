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
  const AuthState({this.signedIn = false, this.error, this.isAdmin = false});

  /// True after a successful login.
  final bool signedIn;

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
