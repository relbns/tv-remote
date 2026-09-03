import 'dart:async';

import 'package:flutter/widgets.dart';

import '../protocol/androidtv/pairing.dart';
import '../protocol/androidtv/remote.dart';
import '../protocol/certificate.dart';
import '../proto/remotemessage.pbenum.dart';
import 'backup.dart';
import 'device.dart';
import 'discovery.dart';
import 'shared_data.dart';

enum LinkState { idle, connecting, connected, pairing, failed }

/// Raised when a device's protocol is not implemented on this platform yet.
class UnsupportedDeviceException implements Exception {
  const UnsupportedDeviceException(this.kind);
  final DeviceKind kind;

  @override
  String toString() =>
      'שליטה ב${kind.label} עדיין לא נתמכת באפליקציית האנדרואיד. '
      'היא כבר עובדת באפליקציית ה-Mac.';
}

/// Everything the screens read and act on.
///
/// One box is active at a time: a session holds an open TLS socket and answers
/// the box's pings, so keeping several alive would cost battery for nothing.
class RemoteController extends ChangeNotifier {
  RemoteController(this._store, this._shared);

  final DeviceStore _store;
  final SharedData _shared;

  AndroidTvRemote? _session;
  AndroidTvPairing? _pairing;
  StreamSubscription<RemoteState>? _stateSub;
  StreamSubscription<void>? _closedSub;
  Timer? _retry;
  AppLifecycleListener? _lifecycle;

  /// True while the app is in the foreground. Reconnecting behind a dark screen
  /// only burns battery — Android suspends the socket anyway.
  bool _foreground = true;

  List<Device> devices = const [];
  Device? current;
  LinkState link = LinkState.idle;
  String? error;
  RemoteState deviceState = const RemoteState();

  /// Packages the box has been seen running that are not saved yet.
  final List<String> learned = [];

  /// Results of the last network sweep. Held here rather than in the page so
  /// they survive a tab change — rescanning a whole subnet to see a list you
  /// already had is a poor trade.
  final List<Discovered> found = [];
  bool scanning = false;
  StreamSubscription<Discovered>? _sweep;

  int get defaultTab => _store.defaultTab;
  Future<void> setDefaultTab(int index) async {
    await _store.setDefaultTab(index);
    notifyListeners();
  }

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

  Future<void> load() async {
    // The socket does not survive the screen going off: Android suspends the
    // app and the box drops the session when its pings go unanswered. Coming
    // back to the foreground is the moment to rebuild it.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        if (!isConnected) unawaited(connect());
      },
      onHide: () => _foreground = false,
      onPause: () => _foreground = false,
    );

    devices = _store.devices();
    await refreshPaired();
    current ??= devices.isEmpty ? null : devices.first;
    notifyListeners();
    if (current != null) unawaited(connect());
  }

  /* ---------------- devices ---------------- */

  Future<void> add(Device device) async {
    await _store.upsert(device);
    devices = _store.devices();
    current ??= device;
    notifyListeners();
  }

  /// Give a device a name that means something to the person using it —
  /// "סלון" beats "ממיר" once there is more than one house involved.
  Future<void> rename(Device device, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _store.upsert(device.copyWith(name: trimmed));
    devices = _store.devices();
    if (current?.id == device.id) {
      current = devices.firstWhere((d) => d.id == device.id);
    }
    notifyListeners();
  }

  Future<void> remove(String id) async {
    if (current?.id == id) await _disconnect();
    await _store.remove(id);
    devices = _store.devices();
    if (current?.id == id) current = devices.isEmpty ? null : devices.first;
    notifyListeners();
  }

  Future<void> select(Device device) async {
    if (current?.id == device.id) return;
    await _disconnect();
    current = device;
    notifyListeners();
    await connect();
  }

  bool isPaired(Device device) => _paired.contains(device.id);
  final Set<String> _paired = {};

  Future<void> refreshPaired() async {
    for (final device in devices) {
      if (await _store.certificate(device.id) != null) {
        _paired.add(device.id);
      }
    }
    notifyListeners();
  }

  /* ---------------- pairing ---------------- */

  /// Start pairing; resolves once the box is showing its code.
  Future<void> beginPairing(Device device) async {
    // Only Android TV has a driver on this platform so far. Running its
    // handshake against a webOS or Tizen set just produces a refused socket,
    // which is what shipping a button with nothing behind it looks like.
    if (device.kind != DeviceKind.androidtv) {
      throw UnsupportedDeviceException(device.kind);
    }
    await _disconnect();
    _set(LinkState.pairing, null);

    // A fresh certificate per attempt: reusing one the box already rejected
    // only reproduces the rejection.
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
      _set(LinkState.failed, '$failure');
      rethrow;
    }
  }

  /// Finish pairing with the code from the screen.
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

    current = device;
    await connect();
  }

  Future<void> cancelPairing() async {
    await _pairing?.close();
    _pairing = null;
    _set(LinkState.idle, null);
  }

  /* ---------------- session ---------------- */

  Future<void> connect() async {
    final device = current;
    if (device == null) return;

    final certificate = await _store.certificate(device.id);
    if (certificate == null) {
      _set(LinkState.idle, null);
      return;
    }

    await _disconnect();
    _set(LinkState.connecting, null);

    final session = AndroidTvRemote(
      host: device.host,
      certificate: certificate,
    );
    _session = session;
    _stateSub = session.states.listen(_onState);
    _closedSub = session.closed.listen((_) => _onSessionClosed());
    // Protocol errors are surfaced, not swallowed: a silent failure here looks
    // exactly like a button that does nothing.
    session.errors.listen((error) => _set(link, '$error'));

    try {
      await session.connect();
      _set(LinkState.connected, null);
    } on Object catch (failure) {
      _session = null;
      _set(LinkState.failed, '$failure');
      _scheduleRetry();
    }
  }

  void _onState(RemoteState state) {
    deviceState = state;
    final package = state.currentApp;
    if (package != null &&
        !_shared.ignoredPackages.contains(package) &&
        !_savedPackages.contains(package)) {
      unawaited(saveLearned(package));
    }
    notifyListeners();
  }

  /// The session ended on its own. Say so, then try to rebuild it — but only
  /// while someone is looking at the app.
  void _onSessionClosed() {
    if (link == LinkState.connected) _set(LinkState.failed, null);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (!_foreground) return;
    _retry = Timer(const Duration(seconds: 3), () {
      if (!isConnected && _foreground) unawaited(connect());
    });
  }

  Future<void> _disconnect() async {
    _retry?.cancel();
    _retry = null;
    await _closedSub?.cancel();
    _closedSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _session?.close();
    _session = null;
    deviceState = const RemoteState();
  }

  /* ---------------- commands ---------------- */

  bool get isConnected => link == LinkState.connected;

  /// Send a command from the shared vocabulary, e.g. `up`, `ok`, `volup`.
  void send(String command) {
    final session = _session;
    if (session == null) return;

    final name = _shared.androidKeyNames[command];
    if (name == null) {
      _set(link, 'פקודה לא נתמכת: $command');
      return;
    }
    final code = RemoteKeyCode.values.firstWhere(
      (value) => value.name == name,
      orElse: () => RemoteKeyCode.KEYCODE_UNKNOWN,
    );
    if (code == RemoteKeyCode.KEYCODE_UNKNOWN) {
      _set(link, 'קוד מקש חסר: $name');
      return;
    }
    session.sendKey(code.value);
  }

  void sendText(String text) => _session?.sendText(text);

  void launch(String target) => _session?.sendAppLink(target);

  /* ---------------- backup ---------------- */

  /// Collect the current setup for transfer to another phone.
  Future<Backup> buildBackup({required bool includeCredentials}) async {
    final certificates = <String, ClientCertificate>{};
    if (includeCredentials) {
      for (final device in devices) {
        final certificate = await _store.certificate(device.id);
        if (certificate == null) continue;
        certificates[device.id] = certificate;
      }
    }

    return Backup(
      devices: devices,
      shortcuts: {
        for (final device in devices) device.id: ?_store.shortcuts(device.id),
      },
      defaultTab: _store.defaultTab,
      certificates: certificates,
    );
  }

  /// Merge a backup into this phone. Returns how many devices it added or
  /// updated. Existing pairings are kept unless the backup carries one, so
  /// importing settings can never cost you a pairing you already have.
  Future<int> applyBackup(Backup backup) async {
    for (final device in backup.devices) {
      await _store.upsert(device);
    }
    for (final entry in backup.shortcuts.entries) {
      await _store.saveShortcuts(entry.key, entry.value);
    }
    for (final entry in backup.certificates.entries) {
      await _store.saveCertificate(entry.key, entry.value);
      _paired.add(entry.key);
    }
    await _store.setDefaultTab(backup.defaultTab);

    devices = _store.devices();
    current ??= devices.isEmpty ? null : devices.first;
    notifyListeners();

    if (current != null && isPaired(current!)) unawaited(connect());
    return backup.devices.length;
  }

  /* ---------------- shortcuts ---------------- */

  /// Shortcuts for the current device — only apps this box has actually been
  /// seen running.
  ///
  /// The protocol cannot be asked what is installed, so a fixed catalogue is a
  /// guess. What the box does report is the foreground app on every change, and
  /// an app that ran here is by definition installed here.
  List<AppEntry> shortcuts() {
    final device = current;
    if (device == null) return const [];
    return _store.shortcuts(device.id) ?? const [];
  }

  /// Entries from the shared catalogue that are not saved yet, offered as a
  /// shortcut for apps you have not opened since installing.
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

  Future<void> addShortcut(AppEntry entry) async {
    final device = current;
    if (device == null) return;
    await _store.saveShortcuts(device.id, [...shortcuts(), entry]);
    notifyListeners();
  }

  Set<String> get _savedPackages => {
    for (final app in shortcuts())
      if (app.package != null) app.package!,
  };

  /// A friendly name for a package the box reported.
  String labelFor(String package) =>
      _shared.friendlyNames[package] ?? _prettify(package);

  Future<void> saveLearned(String package) async {
    final device = current;
    if (device == null) return;

    final known = _shared.catalog
        .where((a) => a.package == package)
        .firstOrNull;
    await addShortcut(
      AppEntry(
        label: known?.label ?? labelFor(package),
        launch: known?.launch ?? 'intent:#Intent;package=$package;end',
        package: package,
        color: known?.color,
      ),
    );
    learned.remove(package);
  }

  Future<void> removeShortcut(AppEntry entry) async {
    final device = current;
    if (device == null) return;
    await _store.saveShortcuts(
      device.id,
      shortcuts().where((app) => app.launch != entry.launch).toList(),
    );
    notifyListeners();
  }

  static String _prettify(String package) {
    const noise = {'com', 'org', 'il', 'co', 'net', 'android', 'tv', 'app'};
    final segment = package
        .split('.')
        .where((part) => !noise.contains(part))
        .lastOrNull;
    if (segment == null || segment.isEmpty) return package;
    return segment[0].toUpperCase() + segment.substring(1);
  }

  void _set(LinkState next, String? failure) {
    link = next;
    error = failure;
    notifyListeners();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    unawaited(_sweep?.cancel());
    unawaited(_disconnect());
    unawaited(_pairing?.close());
    super.dispose();
  }
}
