/// API keys: the calls to make them, list them and revoke them.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/server_address.dart';

/// One API key, without the key itself.
@immutable
class ApiKeyInfo {
  /// Creates the info.
  const ApiKeyInfo({
    required this.id,
    required this.name,
    required this.prefix,
    required this.createdAt,
    this.lastUsedAt,
  });

  /// Parses a key from the API.
  factory ApiKeyInfo.fromJson(Map<String, dynamic> j) => ApiKeyInfo(
        id: '${j['id']}',
        name: '${j['name']}',
        prefix: '${j['prefix']}',
        createdAt: DateTime.parse('${j['created_at']}').toLocal(),
        lastUsedAt: j['last_used_at'] == null
            ? null
            : DateTime.parse('${j['last_used_at']}').toLocal(),
      );

  /// Id of the key.
  final String id;

  /// What the user calls the key.
  final String name;

  /// The first characters of the key, to tell keys apart.
  final String prefix;

  /// When the key was made.
  final DateTime createdAt;

  /// When a tool used the key last, or null when it was never used.
  final DateTime? lastUsedAt;
}

/// A key that was just made: the info and the key itself, which the server
/// shows only this once.
@immutable
class NewApiKey {
  /// Creates the result.
  const NewApiKey(this.info, this.key);

  /// The info of the key.
  final ApiKeyInfo info;

  /// The key. It cannot be read again.
  final String key;
}

/// `/me/api-keys`.
class ApiKeysApi {
  /// Creates the client.
  ApiKeysApi(this._dio);

  final Dio _dio;

  /// `GET /me/api-keys`: the keys of the user, the newest first.
  Future<List<ApiKeyInfo>> list() async {
    final r = await _dio.get<Object?>('/me/api-keys');
    return [
      for (final k in (r.data as List? ?? const []))
        ApiKeyInfo.fromJson(k as Map<String, dynamic>),
    ];
  }

  /// `POST /me/api-keys`: makes a key called [name].
  Future<NewApiKey> create(String name) async {
    final r = await _dio.post<Object?>('/me/api-keys', data: {'name': name});
    final json = r.data! as Map<String, dynamic>;
    return NewApiKey(ApiKeyInfo.fromJson(json), '${json['key']}');
  }

  /// `DELETE /me/api-keys/{id}`: the tool that uses the key is signed out.
  Future<void> revoke(String id) => _dio.delete<Object?>('/me/api-keys/$id');
}

/// Provides the API keys client.
final apiKeysApiProvider =
    Provider<ApiKeysApi>((ref) => ApiKeysApi(ref.watch(dioProvider)));

/// The keys of the user.
final apiKeysProvider = FutureProvider.autoDispose<List<ApiKeyInfo>>(
    (ref) => ref.watch(apiKeysApiProvider).list());

/// The address of the MCP server: the server of the app and `/mcp`.
final mcpUrlProvider = Provider<String>((ref) {
  const suffix = '/api/v1';
  final api = ref.watch(apiBaseUrlProvider);
  final base =
      api.endsWith(suffix) ? api.substring(0, api.length - suffix.length) : api;
  return '$base/mcp';
});

/// The line that adds tefteri to Claude Code.
String claudeCodeCommand(String url, String key) =>
    'claude mcp add --transport http tefteri $url '
    '--header "Authorization: Bearer $key"';

/// The settings that most other MCP clients take (a JSON file).
String mcpClientConfig(String url, String key) => '''{
  "mcpServers": {
    "tefteri": {
      "type": "http",
      "url": "$url",
      "headers": { "Authorization": "Bearer $key" }
    }
  }
}''';
