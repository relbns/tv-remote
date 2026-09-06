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

/// A screen and a source treated as one remote.
///
/// Commands are routed to whichever half should handle them: navigation to the
/// box, volume and input to the screen, power to both.
class Room {
  const Room({
    required this.id,
    required this.name,
    required this.displayId,
    required this.sourceId,
    this.routing = 'auto',
  });

  final String id;
  final String name;

  /// The television.
  final String displayId;

  /// The box producing the picture.
  final String sourceId;

  /// Where volume, power and input go: 'auto', 'display' or 'source'.
  ///
  /// Per set rather than global — one room's box relays volume to its screen
  /// and another's does not, and no single answer fits both.
  final String routing;

  Room copyWith({String? name, String? routing}) => Room(
    id: id,
    name: name ?? this.name,
    displayId: displayId,
    sourceId: sourceId,
    routing: routing ?? this.routing,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'displayId': displayId,
    'sourceId': sourceId,
    'routing': routing,
  };

  factory Room.fromJson(Map<String, dynamic> json) => Room(
    id: json['id'] as String,
    name: json['name'] as String,
    displayId: json['displayId'] as String,
    sourceId: json['sourceId'] as String,
    routing: json['routing'] as String? ?? 'auto',
  );
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
    // A set missing half of itself is not a set.
    await saveRooms(
      rooms().where((r) => r.displayId != id && r.sourceId != id).toList(),
    );
    await _secure.delete(key: 'cert.$id');
    await _secure.delete(key: 'webos.$id');
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

  /// webOS issues a client key instead of a certificate. Same role, same place:
  /// it is what proves this phone to that television.
  Future<String?> webosKey(String deviceId) =>
      _secure.read(key: 'webos.$deviceId');

  Future<void> saveWebosKey(String deviceId, String key) =>
      _secure.write(key: 'webos.$deviceId', value: key);

  /// Samsung issues a token, again the same role and the same place.
  Future<String?> tizenToken(String deviceId) =>
      _secure.read(key: 'tizen.$deviceId');

  Future<void> saveTizenToken(String deviceId, String token) =>
      _secure.write(key: 'tizen.$deviceId', value: token);

  /// Whatever credential this device's protocol uses.
  Future<bool> hasCredential(Device device) async => switch (device.kind) {
    DeviceKind.androidtv => await certificate(device.id) != null,
    DeviceKind.webos => await webosKey(device.id) != null,
    DeviceKind.tizen => await tizenToken(device.id) != null,
  };

  /* ---------------- rooms ---------------- */

  static const _roomsKey = 'rooms';

  List<Room> rooms() {
    final raw = _prefs.getString(_roomsKey);
    if (raw == null) return const [];
    return [
      for (final entry in jsonDecode(raw) as List)
        Room.fromJson(entry as Map<String, dynamic>),
    ];
  }

  Future<void> saveRooms(List<Room> rooms) => _prefs.setString(
    _roomsKey,
    jsonEncode([for (final room in rooms) room.toJson()]),
  );

  Future<void> upsertRoom(Room room) async {
    final all = rooms().toList();
    final index = all.indexWhere((r) => r.id == room.id);
    if (index == -1) {
      all.add(room);
    } else {
      all[index] = room;
    }
    await saveRooms(all);
  }

  Future<void> removeRoom(String id) async =>
      saveRooms(rooms().where((r) => r.id != id).toList());

  /* ---------------- preferences ---------------- */

  /// Which tab the app opens on. Defaults to the remote: that is what the app
  /// is for, and the other tabs are places you visit once.
  int get defaultTab => _prefs.getInt('defaultTab') ?? 0;
  Future<void> setDefaultTab(int index) => _prefs.setInt('defaultTab', index);

  /// Where volume, power and input should go in a set.
  ///
  /// 'auto' follows the shared routing table — screen first. Some setups work
  /// better the other way: a box whose own volume actually drives the output,
  /// or a screen that ignores what it is sent.
  String get routing => _prefs.getString('routing') ?? 'auto';
  Future<void> setRouting(String value) => _prefs.setString('routing', value);

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
  const AppEntry({
    required this.label,
    required this.launch,
    this.package,
    this.color,
  });

  final String label;
  final String launch;
  final String? package;

  /// Brand colour as `#RRGGBB`; null for a learned app we have no colour for.
  final String? color;

  Map<String, dynamic> toJson() => {
    'label': label,
    'launch': launch,
    if (package != null) 'package': package,
    if (color != null) 'color': color,
  };

  factory AppEntry.fromJson(Map<String, dynamic> json) => AppEntry(
    label: json['label'] as String,
    launch: json['launch'] as String,
    package: json['package'] as String?,
    color: json['color'] as String?,
  );
}
