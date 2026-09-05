import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// A newer release than the one installed.
class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.downloadUrl,
    this.notes,
  });

  final String version;
  final String downloadUrl;
  final String? notes;
}

/// Checks GitHub for a newer build.
///
/// The app is installed by hand, so nothing tells a person a new version
/// exists. Releases carry an unversioned asset name, which is what makes the
/// download link stable enough to point at directly.
abstract final class Updates {
  static const _owner = 'relbns';
  static const _repo = 'tv-remote';
  static const _asset = 'tv-remote-arm64.apk';

  static Future<AvailableUpdate?> check() async {
    final installed = (await PackageInfo.fromPlatform()).version;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/$_owner/$_repo/releases/latest',
        ),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;

      final json = jsonDecode(
        await response.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      final tag = json['tag_name'] as String? ?? '';
      final latest = tag.replaceFirst(RegExp(r'^[a-z]+-v'), '');
      if (latest.isEmpty || !_isNewer(latest, installed)) return null;

      return AvailableUpdate(
        version: latest,
        downloadUrl:
            'https://github.com/$_owner/$_repo/releases/latest/download/$_asset',
        notes: json['body'] as String?,
      );
    } on Object {
      // No network, rate limited, offline entirely — an update check is never
      // worth an error in someone's face.
      return null;
    } finally {
      client.close();
    }
  }

  /// Compare dotted versions numerically, so 0.10.0 beats 0.9.0.
  static bool _isNewer(String candidate, String installed) {
    List<int> parts(String v) => [
      for (final piece in v.split('.').take(3))
        int.tryParse(piece.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
    ];
    final a = parts(candidate);
    final b = parts(installed);
    for (var i = 0; i < 3; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }
}
