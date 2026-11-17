import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'muse_sync_config.dart';

Future<Map<String, dynamic>> fetchMuseChanges(
  MuseSyncConfig config,
  String token,
) async {
  if (token.length < 32 || token.contains(RegExp(r'[\r\n]'))) {
    throw const FormatException('Invalid sync credential');
  }
  final uri = museServerUri(config.url).replace(
    path: '/v1/entries',
    queryParameters: {'cursor': '${config.cursor}'},
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    return await (() async {
      final request = await client.getUrl(uri);
      // A redirect must never forward the credential to another origin.
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Sync HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw const FormatException('Sync response too large');
        }
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    })().timeout(const Duration(seconds: 30));
  } finally {
    client.close(force: true);
  }
}
