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
  const AuthState({this.signedIn = false, this.error});

  /// True after a successful login.
  final bool signedIn;

  /// Human-readable error from the last attempt, if any.
  final String? error;
}

/// Controller for login and logout; also a [Listenable] for the router.
class AuthController extends StateNotifier<AuthState> with ChangeNotifier {
  /// Creates a controller using [_ref] for the API client.
  AuthController(this._ref) : super(const AuthState());

  final Ref _ref;

  @override
  set state(AuthState value) {
    super.state = value;
    notifyListeners();
  }

  /// Signs in with [username] and [password].
  Future<void> login(String username, String password) async {
    try {
      final r = await _ref.read(dioProvider).post<Map<String, dynamic>>(
        '/auth/login',
        data: {'username': username, 'password': password},
      );
      _ref.read(tokenStoreProvider.notifier).set(r.data!['token'] as String);
      state = const AuthState(signedIn: true);
    } on DioException catch (e) {
      final detail = (e.response?.data is Map)
          ? (e.response!.data as Map)['detail']?.toString()
          : null;
      state = AuthState(error: detail ?? 'Cannot reach the server');
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
