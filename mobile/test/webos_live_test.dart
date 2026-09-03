import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/src/protocol/webos/webos.dart';

/// Live check against a television on the network. Skipped unless WEBOS_HOST is
/// set, so it never runs in CI.
///
///   WEBOS_HOST=192.168.1.42 flutter test test/webos_live_test.dart
void main() {
  final host = Platform.environment['WEBOS_HOST'];

  test(
    'connects and reaches the on-screen prompt',
    () async {
      final manifest = jsonDecode(
        File('assets/shared/webos_pairing.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      manifest.remove(r'$comment');

      final client = WebosClient(
        host: host!,
        registration: manifest,
        clientKey: Platform.environment['WEBOS_KEY'],
      );

      final prompted = <String>[];
      client.prompts.listen((_) => prompted.add('prompt'));
      client.clientKeys.listen((key) {
        prompted.add('key');
        File('/tmp/webos-key.txt').writeAsStringSync(key);
        // ignore: avoid_print
        print('CLIENT_KEY=$key');
      });

      await client.connect().timeout(
        const Duration(seconds: 60),
        onTimeout: () =>
            throw StateError('לא התקבלה תשובה — האם אישרת על המסך?'),
      );

      // ignore: avoid_print
      print('✓ רשום. אירועים: $prompted');

      final power = await client.request(
        'ssap://com.webos.service.tvpower/power/getPowerState',
      );
      // ignore: avoid_print
      print('מצב הפעלה: $power');

      await client.dispose();
    },
    skip: host == null ? 'WEBOS_HOST לא הוגדר' : null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
