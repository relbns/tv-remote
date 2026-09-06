import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../protocol/androidtv/pairing.dart';
import '../protocol/tizen/tizen.dart';
import '../protocol/androidtv/remote.dart';
import '../protocol/certificate.dart';
import 'backup.dart';
import 'device.dart';
import 'discovery.dart';
import 'session.dart';
import 'shared_data.dart';
import 'target.dart';
import 'updates.dart';

enum LinkState { idle, connecting, connected, pairing, failed }

/// Raised when a device's protocol is not implemented on this platform yet.
/// Turn a failure into something worth reading.
///
/// Raw exception text names a socket and an errno; it tells the person holding
/// the phone nothing they can act on. These messages say what to try instead.
String describeFailure(Object failure) {
  if (failure is SocketException) {
    return 'אין קשר עם המכשיר — ודא שאתה על אותה רשת Wi-Fi והמכשיר דלוק';
  }
  if (failure is HandshakeException) {
    return 'החיבור המאובטח נכשל. אם המכשיר אופס, הסר אותו וצמד מחדש';
  }
  if (failure is TimeoutException) return 'המכשיר לא הגיב בזמן';
  if (failure is UnsupportedCommand ||
      failure is UnsupportedDeviceException ||
      failure is AndroidTvPairingException ||
      failure is TizenException ||
      failure is BackupException) {
    return '$failure';
  }
  return 'משהו השתבש. נסה שוב';
}

class UnsupportedDeviceException implements Exception {
  const UnsupportedDeviceException(this.kind);
  final DeviceKind kind;

  @override
  String toString() => 'שליטה ב${kind.label} עדיין לא נתמכת כאן';
}

/// Everything the screens read and act on.
class RemoteController extends ChangeNotifier {
  RemoteController(this._store, this._shared);

  final DeviceStore _store;
  final SharedData _shared;

  /// One session per device. A set needs both of its halves live at once.
  final Map<String, DeviceSession> _sessions = {};
  final Map<String, List<StreamSubscription<Object?>>> _subs = {};

  AndroidTvPairing? _pairing;
  Map<String, dynamic>? _webosRegistration;
  Timer? _retry;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;

  List<Device> devices = const [];
  List<Room> rooms = const [];
  Target? current;
  LinkState link = LinkState.idle;
  String? error;

  final Set<String> _paired = {};

  /// Set when a newer release exists. Null while unknown or up to date.
  AvailableUpdate? update;

  final List<Discovered> found = [];
  bool scanning = false;
  StreamSubscription<Discovered>? _sweep;

  /* ---------------- targets ---------------- */

  /// Sets first, then any device that is not part of one.
  List<Target> get targets {
    final byId = {for (final device in devices) device.id: device};
    final grouped = <String>{};
    final out = <Target>[];

    for (final room in rooms) {
      final display = byId[room.displayId];
      final source = byId[room.sourceId];
      if (display == null || source == null) continue;
      grouped
        ..add(room.displayId)
        ..add(room.sourceId);
      out.add(Target.forRoom(room, display: display, source: source));
    }
    for (final device in devices) {
      if (!grouped.contains(device.id)) out.add(Target.forDevice(device));
    }
    return out;
  }

  Target? targetFor(String id) {
    for (final target in targets) {
      if (target.id == id) return target;
    }
    return null;
  }

  /// State to show for the current target: the screen's volume, the box's app.
  RemoteState get deviceState {
    final target = current;
    if (target == null) return const RemoteState();
    final source = _sessions[target.source?.id]?.state;
    final display = _sessions[target.display?.id]?.state;
    return RemoteState(
      powered: display?.powered ?? source?.powered,
      volume: display?.volume ?? source?.volume,
      volumeLevel: display?.volumeLevel ?? source?.volumeLevel,
      volumeMax: display?.volumeMax ?? source?.volumeMax,
      muted: display?.muted ?? source?.muted,
      currentApp: source?.currentApp ?? display?.currentApp,
    );
  }

  /// A target is live when at least one of its devices is.
  bool get isConnected =>
      current?.devices.any((d) => _sessions[d.id]?.isConnected ?? false) ??
      false;

  bool isDeviceConnected(String id) => _sessions[id]?.isConnected ?? false;
  bool isPaired(Device device) => _paired.contains(device.id);

  /// Commands the current target can carry out, from either half.
  Set<String> get capabilities => {
    for (final device in current?.devices ?? const <Device>[])
      ...?_sessions[device.id]?.capabilities,
  };

  /* ---------------- lifecycle ---------------- */

  Future<void> load() async {
    await _store.migrateTabIndices();
    // The socket does not survive the screen going off: Android suspends the
    // app and the box drops the session when its pings go unanswered. Coming
    // back to the foreground is the moment to rebuild it.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        unawaited(_connectCurrent());
      },
      onHide: () => _foreground = false,
      onPause: () => _foreground = false,
    );

    _webosRegistration = await loadWebosRegistration();
    devices = _store.devices();
    rooms = _store.rooms();
    await _refreshPaired();
    current ??= targets.firstOrNull;
    notifyListeners();
    unawaited(_connectCurrent());
    unawaited(checkForUpdate());
  }

  Future<void> checkForUpdate() async {
    final found = await Updates.check();
    if (found == null) return;
    update = found;
    notifyListeners();
  }

  Future<void> _refreshPaired() async {
    _paired.clear();
    for (final device in devices) {
      if (await _store.hasCredential(device)) _paired.add(device.id);
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _retry?.cancel();
    unawaited(_sweep?.cancel());
    for (final id in _sessions.keys.toList()) {
      unawaited(_closeSession(id));
    }
    unawaited(_pairing?.close());
    super.dispose();
  }

  /* ---------------- sessions ---------------- */

  Future<void> _connectCurrent() async {
    final target = current;
    if (target == null) return;

    _set(LinkState.connecting, null);
    var any = false;
    for (final device in target.devices) {
      if (await _openSession(device)) any = true;
    }
    _set(any ? LinkState.connected : LinkState.failed, error);
    if (!any) _scheduleRetry();
  }

  Future<bool> _openSession(Device device) async {
    if (_sessions[device.id]?.isConnected ?? false) return true;
    await _closeSession(device.id);

    final DeviceSession session;
    switch (device.kind) {
      case DeviceKind.androidtv:
        final certificate = await _store.certificate(device.id);
        if (certificate == null) return false;
        session = AndroidTvSession(
          device: device,
          certificate: certificate,
          shared: _shared,
        );
      case DeviceKind.webos:
        final key = await _store.webosKey(device.id);
        if (key == null) return false;
        session = WebosSession(
          device: device,
          registration: _webosRegistration ?? const {},
          shared: _shared,
          clientKey: key,
        );
      case DeviceKind.tizen:
        final token = await _store.tizenToken(device.id);
        if (token == null) return false;
        session = TizenSession(device: device, shared: _shared, token: token);
    }

    _sessions[device.id] = session;
    _subs[device.id] = [
      session.states.listen((_) => _onState(device)),
      session.closed.listen((_) => _onClosed(device)),
      // Same reasoning: a socket that drops is reported by the connection
      // state, not by a message the user has to dismiss.
      session.errors.listen((_) {}),
    ];

    try {
      await session.connect();
      notifyListeners();
      return true;
    } on Object {
      // Not being able to reach a saved device is ordinary — it is switched
      // off, or you are not at home. The dot already says so, and a message
      // about it would fire on every launch away from the house.
      await _closeSession(device.id);
      return false;
    }
  }

  Future<void> _closeSession(String id) async {
    for (final sub
        in _subs.remove(id) ?? const <StreamSubscription<Object?>>[]) {
      await sub.cancel();
    }
    final session = _sessions.remove(id);
    await session?.close();
  }

  void _onState(Device device) {
    final package = _sessions[device.id]?.state.currentApp;
    if (device.kind == DeviceKind.androidtv &&
        package != null &&
        !_shared.ignoredPackages.contains(package) &&
        !_savedPackages(device.id).contains(package)) {
      unawaited(_learn(device, package));
    }
    notifyListeners();
  }

  void _onClosed(Device device) {
    if (link == LinkState.connected && !isConnected) {
      _set(LinkState.failed, null);
    }
    notifyListeners();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (!_foreground) return;
    _retry = Timer(const Duration(seconds: 3), () {
      if (_foreground && !isConnected) unawaited(_connectCurrent());
    });
  }

  /* ---------------- commands ---------------- */

  /// Send a command to whichever half of the target should handle it.
  ///
  /// The preference is a starting point, not a rule: if the preferred device is
  /// missing, offline, or cannot carry the command, the other one is tried.
  /// That fallback is what makes volume work on a screen with no network — the
  /// box relays it down the HDMI cable instead.
  Future<void> send(String command, [Object? arg]) async {
    final target = current;
    if (target == null) return;

    // 'auto' follows the shared routing table; an explicit choice overrides it
    // for the commands where the two halves disagree about who should act.
    final routable = _shared.preferDisplay.contains(command);
    final preferDisplay = switch (routingFor(target)) {
      'display' => routable,
      'source' => false,
      _ => routable,
    };
    final order = preferDisplay
        ? [target.display, target.source]
        : [target.source, target.display];

    for (final device in order) {
      if (device == null) continue;
      final session = _sessions[device.id];
      if (session == null || !session.isConnected) continue;
      if (!session.capabilities.contains(command)) continue;
      try {
        await session.send(command, arg);
        return;
      } on Object catch (failure) {
        _set(link, describeFailure(failure));
        return;
      }
    }
    _set(link, isConnected ? 'אין מכשיר שתומך בפקודה הזו' : 'אין חיבור פעיל');
  }

  Future<void> sendText(String text) => send('text', text);
  Future<void> launch(String target) => send('launch', target);

  /// Power the whole target: both halves of a set, together.
  Future<void> power() async {
    final target = current;
    if (target == null) return;

    // With an explicit choice, power only touches the half that was chosen.
    final chosen = switch (routingFor(target)) {
      'display' => [?target.display],
      'source' => [?target.source],
      _ => target.devices,
    };

    for (final device in chosen) {
      final session = _sessions[device.id];
      if (session == null || !session.isConnected) continue;
      // A screen understands "turn off"; a box toggles its own standby.
      final command = device.kind.isDisplay ? 'tvpower' : 'power';
      try {
        await session.send(command);
      } on Object catch (failure) {
        _set(link, describeFailure(failure));
      }
    }
  }

  /* ---------------- devices ---------------- */

  Future<void> add(Device device) async {
    await _store.upsert(device);
    devices = _store.devices();
    current ??= targets.firstOrNull;
    notifyListeners();
  }

  Future<void> rename(Device device, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _store.upsert(device.copyWith(name: trimmed));
    devices = _store.devices();
    _reselect();
  }

  Future<void> remove(String id) async {
    await _closeSession(id);
    await _store.remove(id);
    devices = _store.devices();
    rooms = _store.rooms();
    _paired.remove(id);
    _reselect();
  }

  Future<void> select(Target target) async {
    if (current?.id == target.id) return;
    for (final id in _sessions.keys.toList()) {
      await _closeSession(id);
    }
    current = target;
    notifyListeners();
    await _connectCurrent();
  }

  void _reselect() {
    current = targetFor(current?.id ?? '') ?? targets.firstOrNull;
    notifyListeners();
  }

  /* ---------------- rooms ---------------- */

  Future<void> saveRoom({
    String? id,
    required String name,
    required String displayId,
    required String sourceId,
  }) async {
    await _store.upsertRoom(
      Room(
        id: id ?? 'room-${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim(),
        displayId: displayId,
        sourceId: sourceId,
      ),
    );
    rooms = _store.rooms();
    _reselect();
  }

  Future<void> removeRoom(String id) async {
    await _store.removeRoom(id);
    rooms = _store.rooms();
    _reselect();
  }

  /* ---------------- pairing ---------------- */

  /// Start pairing. Android TV shows a code; webOS shows a prompt to accept.
  Future<void> beginPairing(Device device) async {
    _set(LinkState.pairing, null);

    switch (device.kind) {
      case DeviceKind.androidtv:
        // A fresh certificate per attempt: reusing one the box already
        // rejected only reproduces the rejection.
        final certificate = generateClientCertificate(commonName: 'TV Remote');
        final pairing = AndroidTvPairing(
          host: device.host,
          certificate: certificate,
        );
        _pairing = pairing;
        try {
          await pairing.begin();
        } on Object catch (failure) {
          _pairing = null;
          _set(LinkState.failed, describeFailure(failure));
          rethrow;
        }

      case DeviceKind.webos:
        final session = WebosSession(
          device: device,
          registration: _webosRegistration ?? const {},
          shared: _shared,
        );
        // The television waits for a person to accept on screen; connect()
        // only returns once they have.
        final key = session.clientKeys.first;
        try {
          await session.connect();
          await _store.saveWebosKey(device.id, await key);
          _paired.add(device.id);
        } finally {
          await session.close();
        }
        _set(LinkState.idle, null);
        await select(Target.forDevice(device));

      case DeviceKind.tizen:
        final session = TizenSession(device: device, shared: _shared);
        // The set shows its prompt on the first connection and answers with a
        // token only once a person accepts, so the token is the confirmation.
        final token = session.tokens.first;
        try {
          await session.connect();
          await _store.saveTizenToken(
            device.id,
            await token.timeout(const Duration(seconds: 45)),
          );
          _paired.add(device.id);
        } finally {
          await session.close();
        }
        _set(LinkState.idle, null);
        await select(Target.forDevice(device));
    }
  }

  /// Finish Android TV pairing with the code from the screen.
  Future<void> submitCode(Device device, String code) async {
    final pairing = _pairing;
    if (pairing == null) {
      throw const AndroidTvPairingException('הצימוד לא הותחל');
    }

    await pairing.submitCode(code);
    await _store.saveCertificate(device.id, pairing.certificate);
    _paired.add(device.id);
    await pairing.close();
    _pairing = null;

    await select(targetFor(device.id) ?? Target.forDevice(device));
  }

  Future<void> cancelPairing() async {
    await _pairing?.close();
    _pairing = null;
    _set(LinkState.idle, null);
  }

  /* ---------------- discovery ---------------- */

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    found.clear();
    notifyListeners();

    final known = {for (final device in devices) device.host};
    await _sweep?.cancel();
    _sweep = Discovery.sweep().listen(
      (device) {
        if (known.contains(device.host)) return;
        found.add(device);
        notifyListeners();
      },
      onDone: () {
        scanning = false;
        notifyListeners();
      },
    );
  }

  void forgetFound(Discovered device) {
    found.remove(device);
    notifyListeners();
  }

  /* ---------------- channels ---------------- */

  /// The channel list: the user's, if they have edited it, otherwise the seed.
  List<Channel> get channels =>
      _store.channels() ??
      [for (final entry in _shared.channelSeed) Channel.fromJson(entry)];

  bool get channelsAreCustom => _store.channels() != null;

  Future<void> saveChannels(List<Channel> next) async {
    await _store.saveChannels(next);
    notifyListeners();
  }

  Future<void> resetChannels() async {
    await _store.resetChannels();
    notifyListeners();
  }

  /// Key in a channel number, digit by digit, then confirm.
  ///
  /// There is no "go to channel" message in any of these protocols — a remote
  /// presses digits, and so does this.
  Future<void> tuneTo(String number) async {
    for (final digit in number.trim().split('')) {
      if (int.tryParse(digit) == null) continue;
      await send('num$digit');
      // Boxes drop digits sent back to back; this is the gap a thumb leaves.
      await Future<void>.delayed(const Duration(milliseconds: 140));
    }
    if (capabilities.contains('enter')) await send('enter');
  }

  /* ---------------- shortcuts ---------------- */

  /// Only apps the box has actually been seen running.
  List<AppEntry> shortcuts() {
    final id = current?.source?.id;
    if (id == null) return const [];
    return _store.shortcuts(id) ?? const [];
  }

  List<AppEntry> catalogSuggestions() {
    final saved = {for (final app in shortcuts()) app.launch};
    return [
      for (final app in _shared.catalog)
        if (!saved.contains(app.launch))
          AppEntry(
            label: app.label,
            launch: app.launch,
            package: app.package,
            color: app.color,
          ),
    ];
  }

  Set<String> _savedPackages(String deviceId) => {
    for (final app in _store.shortcuts(deviceId) ?? const <AppEntry>[])
      if (app.package != null) app.package!,
  };

  Future<void> _learn(Device device, String package) async {
    final known = _shared.catalog
        .where((a) => a.package == package)
        .firstOrNull;
    await _store.saveShortcuts(device.id, [
      ...?_store.shortcuts(device.id),
      AppEntry(
        label: known?.label ?? labelFor(package),
        launch: known?.launch ?? 'intent:#Intent;package=$package;end',
        package: package,
        color: known?.color,
      ),
    ]);
    notifyListeners();
  }

  Future<void> addShortcut(AppEntry entry) async {
    final id = current?.source?.id;
    if (id == null) return;
    await _store.saveShortcuts(id, [...shortcuts(), entry]);
    notifyListeners();
  }

  Future<void> removeShortcut(AppEntry entry) async {
    final id = current?.source?.id;
    if (id == null) return;
    await _store.saveShortcuts(
      id,
      shortcuts().where((app) => app.launch != entry.launch).toList(),
    );
    notifyListeners();
  }

  String labelFor(String package) =>
      _shared.friendlyNames[package] ?? _prettify(package);

  static String _prettify(String package) {
    const noise = {'com', 'org', 'il', 'co', 'net', 'android', 'tv', 'app'};
    final segment = package
        .split('.')
        .where((part) => !noise.contains(part))
        .lastOrNull;
    if (segment == null || segment.isEmpty) return package;
    return segment[0].toUpperCase() + segment.substring(1);
  }

  /* ---------------- preferences and backup ---------------- */

  int get defaultTab => _store.defaultTab;

  /// Where this target's volume, power and input go.
  ///
  /// A set carries its own choice; a single device follows the app-wide one,
  /// since there is no second half to disagree with.
  String routingFor(Target target) => target.room?.routing ?? _store.routing;

  Future<void> setRouting(Target target, String value) async {
    final room = target.room;
    if (room == null) {
      await _store.setRouting(value);
    } else {
      await _store.upsertRoom(room.copyWith(routing: value));
      rooms = _store.rooms();
      _reselect();
    }
    notifyListeners();
  }

  Future<void> setDefaultTab(int index) async {
    await _store.setDefaultTab(index);
    notifyListeners();
  }

  /// Store one device's pairing, in whatever shape its protocol uses.
  ///
  /// The shape is checked rather than trusted: a backup is a file a person can
  /// edit, and a half-written credential should be skipped, not saved.
  Future<bool> _restoreCredential(
    String deviceId,
    Map<String, String> credential,
  ) async {
    final device = devices.where((d) => d.id == deviceId).firstOrNull;
    if (device == null) return false;
    switch (device.kind) {
      case DeviceKind.androidtv:
        final cert = credential['cert'];
        final key = credential['key'];
        if (cert == null || key == null) return false;
        await _store.saveCertificate(
          deviceId,
          ClientCertificate(certificatePem: cert, privateKeyPem: key),
        );
        return true;
      case DeviceKind.webos:
        final key = credential['clientKey'];
        if (key == null) return false;
        await _store.saveWebosKey(deviceId, key);
        return true;
      case DeviceKind.tizen:
        final token = credential['token'];
        if (token == null) return false;
        await _store.saveTizenToken(deviceId, token);
        return true;
    }
  }

  Future<Map<String, String>?> _credentialFor(Device device) async {
    switch (device.kind) {
      case DeviceKind.androidtv:
        final certificate = await _store.certificate(device.id);
        return certificate?.toJson();
      case DeviceKind.webos:
        final key = await _store.webosKey(device.id);
        return key == null ? null : {'clientKey': key};
      case DeviceKind.tizen:
        final token = await _store.tizenToken(device.id);
        return token == null ? null : {'token': token};
    }
  }

  Future<Backup> buildBackup({required bool includeCredentials}) async {
    final credentials = <String, Map<String, String>>{};
    if (includeCredentials) {
      for (final device in devices) {
        final credential = await _credentialFor(device);
        if (credential != null) credentials[device.id] = credential;
      }
    }

    return Backup(
      devices: devices,
      rooms: rooms,
      shortcuts: {
        for (final device in devices) device.id: ?_store.shortcuts(device.id),
      },
      defaultTab: _store.defaultTab,
      credentials: credentials,
    );
  }

  /// Merge a backup in. Existing pairings are kept unless the backup carries
  /// one, so importing settings can never cost a pairing already held.
  Future<int> applyBackup(Backup backup) async {
    for (final device in backup.devices) {
      await _store.upsert(device);
    }
    for (final room in backup.rooms) {
      await _store.upsertRoom(room);
    }
    for (final entry in backup.shortcuts.entries) {
      await _store.saveShortcuts(entry.key, entry.value);
    }
    for (final entry in backup.credentials.entries) {
      if (await _restoreCredential(entry.key, entry.value)) {
        _paired.add(entry.key);
      }
    }
    final tab = backup.defaultTab;
    if (tab != null) await _store.setDefaultTab(tab);

    devices = _store.devices();
    rooms = _store.rooms();
    _reselect();
    unawaited(_connectCurrent());
    return backup.devices.length;
  }

  void _set(LinkState next, String? failure) {
    link = next;
    error = failure;
    notifyListeners();
  }
}
