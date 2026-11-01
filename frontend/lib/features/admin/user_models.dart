/// Models and providers for admin user management.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// A user account as the admin API returns it.
@immutable
class AdminUser {
  /// Creates a user.
  const AdminUser({
    required this.id,
    required this.username,
    required this.isAdmin,
    required this.timezone,
    required this.disabled,
  });

  /// Reads a user from API JSON.
  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as String,
        username: json['username'] as String,
        isAdmin: json['is_admin'] == true,
        timezone: (json['timezone'] ?? 'UTC') as String,
        disabled: json['disabled'] == true,
      );

  /// User id.
  final String id;

  /// Sign-in name.
  final String username;

  /// True for administrators.
  final bool isAdmin;

  /// IANA time zone name.
  final String timezone;

  /// True when the account cannot sign in.
  final bool disabled;
}

/// Loads all users (admin only).
final usersProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) async {
  final r = await ref.read(dioProvider).get<List<dynamic>>('/users');
  return [
    for (final u in r.data ?? const <dynamic>[])
      AdminUser.fromJson(u as Map<String, dynamic>),
  ];
});
