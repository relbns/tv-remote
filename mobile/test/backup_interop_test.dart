import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/src/data/backup.dart';
import 'package:tv_remote/src/data/device.dart';

/// A backup only its author can read is not a transfer.
///
/// These fixtures were produced by the macOS client and are read here by the
/// phone client's own parser, so the two cannot drift into private formats
/// without a test noticing.
void main() {
  group('גיבוי שנוצר במק', () {
    test('נקרא כקוד דחוס', () {
      final compact = File('test/fixtures/mac-compact.txt').readAsStringSync();
      final backup = Backup.fromCompact(compact);

      expect(backup.devices, hasLength(3));
      expect(backup.devices.map((d) => d.host), contains('192.0.2.1'));
      expect(backup.rooms, hasLength(1));
      expect(
        backup.includesCredentials,
        isFalse,
        reason: 'ייצוא הגדרות בלבד לעולם לא נושא תעודות',
      );
    });

    test('נקרא כקובץ, כולל התעודות', () {
      final json = File('test/fixtures/mac-full.json').readAsStringSync();
      final backup = Backup.fromText(json);

      expect(backup.devices, hasLength(3));
      expect(backup.includesCredentials, isTrue);
      // Each protocol proves itself differently, and all of them have to
      // survive the trip — not only the one that happened to be paired.
      final byKind = {
        for (final device in backup.devices)
          if (backup.credentials[device.id] != null)
            device.kind: backup.credentials[device.id]!,
      };
      expect(
        byKind[DeviceKind.androidtv]?['cert'],
        contains('BEGIN CERTIFICATE'),
      );
      expect(
        byKind[DeviceKind.androidtv]?['key'],
        contains('BEGIN PRIVATE KEY'),
      );
      expect(byKind[DeviceKind.webos]?['clientKey'], isNotEmpty);
    });

    test('סט מגיע עם שני חצאיו', () {
      final backup = Backup.fromText(
        File('test/fixtures/mac-full.json').readAsStringSync(),
      );
      final room = backup.rooms.single;
      final ids = backup.devices.map((d) => d.id).toSet();
      expect(ids, contains(room.sourceId));
      expect(ids, contains(room.displayId));
    });
  });
}
