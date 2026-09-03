import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/certificate.dart';

enum DeviceKind {
  androidtv('ממיר / Android TV', 'ממיר'),
  webos('טלוויזיית LG', 'LG'),
  tizen('טלוויזיית Samsung', 'Samsung');

  const DeviceKind(this.label, this.short);
  final String label;
  final String short;

  bool get isDisplay => this != DeviceKind.androidtv;
}

class Device {
  const Device({
    required this.id,
    required this.kind,
    required this.name,
    required this.host,
    this.mac,
  });

  final String id;
  final DeviceKind kind;
  final String name;
  final String host;
  final String? mac;

  Device copyWith({String? name, String? host, String? mac}) => Device(
    id: id,
    kind: kind,
    name: name ?? this.name,
    host: host ?? this.host,
    mac: mac ?? this.mac,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'host': host,
    if (mac != null) 'mac': mac,
  };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as String,
    kind: DeviceKind.values.byName(json['kind'] as String),
    name: json['name'] as String,
    host: json['host'] as String,
    mac: json['mac'] as String?,
  );

  static String idFor(DeviceKind kind, String host) =>
      '${kind.name}-${host.replaceAll('.', '-')}';
}

/// Persistence.
///
/// Devices and shortcuts are ordinary preferences, but the pairing certificate
/// is the one secret here — it is what proves this phone to the box — so it
/// lives in the platform keystore rather than alongside them.
class DeviceStore {
  DeviceStore(this._prefs, [FlutterSecureStorage? secure])
    : _secure = secure ?? const FlutterSecureStorage();

  static const _devicesKey = 'devices';
  static const _appsPrefix = 'apps.';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static Future<DeviceStore> open() async =>
      DeviceStore(await SharedPreferences.getInstance());

  List<Device> devices() {
    final raw = _prefs.getString(_devicesKey);
    if (raw == null) return const [];
    return [
      for (final entry in jsonDecode(raw) as List)
        Device.fromJson(entry as Map<String, dynamic>),
    ];
  }

  Future<void> saveDevices(List<Device> devices) => _prefs.setString(
    _devicesKey,
    jsonEncode([for (final device in devices) device.toJson()]),
  );

  Future<void> upsert(Device device) async {
    final all = devices().toList();
    final index = all.indexWhere((d) => d.id == device.id);
    if (index == -1) {
      all.add(device);
    } else {
      all[index] = device;
    }
    await saveDevices(all);
  }

  Future<void> remove(String id) async {
    await saveDevices(devices().where((d) => d.id != id).toList());
    await _secure.delete(key: 'cert.$id');
    await _prefs.remove('$_appsPrefix$id');
  }

  /* ---------------- certificates ---------------- */

  Future<ClientCertificate?> certificate(String deviceId) async {
    final raw = await _secure.read(key: 'cert.$deviceId');
    if (raw == null) return null;
    return ClientCertificate.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveCertificate(String deviceId, ClientCertificate cert) =>
      _secure.write(key: 'cert.$deviceId', value: jsonEncode(cert.toJson()));

  /* ---------------- app shortcuts ---------------- */

  List<AppEntry>? shortcuts(String deviceId) {
    final raw = _prefs.getString('$_appsPrefix$deviceId');
    if (raw == null) return null;
    return [
      for (final entry in jsonDecode(raw) as List)
        AppEntry.fromJson(entry as Map<String, dynamic>),
    ];
  }

  Future<void> saveShortcuts(String deviceId, List<AppEntry> apps) =>
      _prefs.setString(
        '$_appsPrefix$deviceId',
        jsonEncode([for (final app in apps) app.toJson()]),
      );
}

/// A saved app shortcut. Mirrors the shared catalogue's shape so a learned
/// package and a catalogue entry are stored the same way.
class AppEntry {
  const AppEntry({required this.label, required this.launch, this.package});

  final String label;
  final String launch;
  final String? package;

  Map<String, dynamic> toJson() => {
    'label': label,
    'launch': launch,
    if (package != null) 'package': package,
  };

  factory AppEntry.fromJson(Map<String, dynamic> json) => AppEntry(
    label: json['label'] as String,
    launch: json['launch'] as String,
    package: json['package'] as String?,
  );
}
