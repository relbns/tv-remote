import 'dart:convert';
import 'dart:io';

import '../protocol/certificate.dart';
import 'device.dart';

/// Moving a setup to another phone.
///
/// Two shapes, because they carry different risk. Settings alone are ordinary
/// data — device addresses, the names you gave them, your app shortcuts — and
/// small enough to travel as a QR code. Adding the pairing certificates makes
/// the second phone work without walking to the television, but the file then
/// *is* the credential, and it is too large for a QR code anyway.
class Backup {
  static const formatVersion = 1;

  const Backup({
    required this.devices,
    required this.shortcuts,
    this.defaultTab,
    this.rooms = const [],
    this.certificates = const {},
  });

  final List<Device> devices;

  /// Sets travel with the devices; a set without both halves is dropped on
  /// import anyway, so nothing needs to be checked here.
  final List<Room> rooms;

  /// Saved app shortcuts, keyed by device id.
  final Map<String, List<AppEntry>> shortcuts;

  /// Nullable on purpose: the desktop client has no tabs, so its backups say
  /// nothing about which one to open, and a missing value must leave the
  /// receiving device's own choice alone rather than reset it.
  final int? defaultTab;

  /// Pairing certificates, keyed by device id. Empty for a settings-only backup.
  final Map<String, ClientCertificate> certificates;

  bool get includesCredentials => certificates.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'v': formatVersion,
    'devices': [for (final device in devices) device.toJson()],
    if (rooms.isNotEmpty) 'rooms': [for (final room in rooms) room.toJson()],
    'apps': {
      for (final entry in shortcuts.entries)
        entry.key: [for (final app in entry.value) app.toJson()],
    },
    if (defaultTab != null) 'defaultTab': defaultTab,
    if (certificates.isNotEmpty)
      'certs': {
        for (final entry in certificates.entries)
          entry.key: entry.value.toJson(),
      },
  };

  factory Backup.fromJson(Map<String, dynamic> json) {
    final version = json['v'] as int? ?? 0;
    if (version > formatVersion) {
      throw const BackupException(
        'הגיבוי נוצר בגרסה חדשה יותר של האפליקציה. עדכן ונסה שוב.',
      );
    }

    return Backup(
      devices: [
        for (final entry in json['devices'] as List? ?? const [])
          Device.fromJson(entry as Map<String, dynamic>),
      ],
      rooms: [
        for (final entry in json['rooms'] as List? ?? const [])
          Room.fromJson(entry as Map<String, dynamic>),
      ],
      shortcuts: {
        for (final entry in (json['apps'] as Map? ?? const {}).entries)
          entry.key as String: [
            for (final app in entry.value as List)
              AppEntry.fromJson(app as Map<String, dynamic>),
          ],
      },
      defaultTab: json['defaultTab'] as int?,
      certificates: {
        for (final entry in (json['certs'] as Map? ?? const {}).entries)
          entry.key as String: ClientCertificate.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      },
    );
  }

  /// Compact form for a QR code: gzip then base64.
  ///
  /// JSON of a few devices compresses to a couple of hundred bytes, well inside
  /// what a phone camera can read in one go. A backup carrying certificates
  /// does not fit and is not offered this way.
  String toCompact() =>
      base64Url.encode(gzip.encode(utf8.encode(jsonEncode(toJson()))));

  static Backup fromCompact(String compact) {
    try {
      final json = jsonDecode(
        utf8.decode(gzip.decode(base64Url.decode(compact.trim()))),
      );
      return Backup.fromJson(json as Map<String, dynamic>);
    } on BackupException {
      rethrow;
    } on Object {
      throw const BackupException('הקוד שנסרק אינו גיבוי תקין');
    }
  }

  /// Readable form for a file, so a person can see what they are sending.
  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  static Backup fromText(String text) {
    try {
      return Backup.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on BackupException {
      rethrow;
    } on Object {
      // A file may hold either shape; fall back to the compact one.
      return fromCompact(text);
    }
  }
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
