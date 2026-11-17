import 'dart:convert';

/// Device-local settings. The read credential lives in Android Keystore storage.
class MuseSyncConfig {
  const MuseSyncConfig({
    this.url = '',
    this.bookId = '',
    this.enabled = false,
    this.cursor = 0,
    this.stream = '',
  });

  final String url;
  final String bookId;
  final bool enabled;
  final int cursor;
  final String stream;

  MuseSyncConfig copyWith({bool? enabled, int? cursor, String? stream}) =>
      MuseSyncConfig(
        url: url,
        bookId: bookId,
        enabled: enabled ?? this.enabled,
        cursor: cursor ?? this.cursor,
        stream: stream ?? this.stream,
      );

  String encode() => jsonEncode({
    'url': url,
    'bookId': bookId,
    'enabled': enabled,
    'cursor': cursor,
    'stream': stream,
  });

  static MuseSyncConfig decode(String? raw) {
    if (raw == null) return const MuseSyncConfig();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return MuseSyncConfig(
        url: json['url'] as String? ?? '',
        bookId: json['bookId'] as String? ?? '',
        enabled: json['enabled'] == true,
        cursor: json['cursor'] as int? ?? 0,
        stream: json['stream'] as String? ?? '',
      );
    } catch (_) {
      // Corrupt local configuration disables network synchronization.
      return const MuseSyncConfig();
    }
  }
}

Uri museServerUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('An HTTPS server origin is required');
  }
  return uri.replace(path: '');
}
