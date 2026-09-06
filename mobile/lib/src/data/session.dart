import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../protocol/androidtv/remote.dart';
import '../protocol/certificate.dart';
import '../protocol/tizen/tizen.dart';
import '../protocol/webos/webos.dart';
import '../proto/remotemessage.pbenum.dart';
import 'device.dart';
import 'shared_data.dart';

/// One live connection to one device, with the protocol hidden.
///
/// A set points at two devices that speak entirely different protocols, so the
/// thing above them has to be able to say "volume up" without knowing which.
abstract class DeviceSession {
  Device get device;

  Stream<RemoteState> get states;
  Stream<Object> get errors;
  Stream<void> get closed;

  RemoteState get state;
  bool get isConnected;

  /// Commands this session can actually carry out.
  Set<String> get capabilities;

  Future<void> connect();
  Future<void> close();

  /// Run a command from the shared vocabulary. Throws if unsupported.
  Future<void> send(String command, [Object? arg]);
}

/* ---------------- Android TV ---------------- */

class AndroidTvSession implements DeviceSession {
  AndroidTvSession({
    required this.device,
    required ClientCertificate certificate,
    required SharedData shared,
  }) : _shared = shared,
       _remote = AndroidTvRemote(host: device.host, certificate: certificate);

  @override
  final Device device;

  final SharedData _shared;
  final AndroidTvRemote _remote;

  @override
  Stream<RemoteState> get states => _remote.states;
  @override
  Stream<Object> get errors => _remote.errors;
  @override
  Stream<void> get closed => _remote.closed;
  @override
  RemoteState get state => _remote.state;
  @override
  bool get isConnected => _remote.isConnected;

  @override
  Set<String> get capabilities => {
    ..._shared.androidKeyNames.keys,
    'text',
    'applink',
  };

  @override
  Future<void> connect() => _remote.connect();
  @override
  Future<void> close() => _remote.close();

  @override
  Future<void> send(String command, [Object? arg]) async {
    if (command == 'text') {
      return _remote.sendText('${arg ?? ''}');
    }
    if (command == 'applink' || command == 'launch') {
      return _remote.sendAppLink('$arg');
    }

    final name = _shared.androidKeyNames[command];
    if (name == null) throw UnsupportedCommand(command);
    final code = RemoteKeyCode.values.firstWhere(
      (value) => value.name == name,
      orElse: () => RemoteKeyCode.KEYCODE_UNKNOWN,
    );
    if (code == RemoteKeyCode.KEYCODE_UNKNOWN) {
      throw UnsupportedCommand(command);
    }
    _remote.sendKey(code.value);
  }
}

/* ---------------- LG webOS ---------------- */

class WebosSession implements DeviceSession {
  WebosSession({
    required this.device,
    required Map<String, dynamic> registration,
    required SharedData shared,
    String? clientKey,
  }) : _shared = shared,
       _client = WebosClient(
         host: device.host,
         registration: registration,
         clientKey: clientKey,
       );

  @override
  final Device device;

  final SharedData _shared;
  final WebosClient _client;

  final _states = StreamController<RemoteState>.broadcast();
  RemoteState _state = const RemoteState();

  /// Emits the key the television issues once its prompt is accepted; store it.
  Stream<String> get clientKeys => _client.clientKeys;

  /// Emits when the television puts its confirmation prompt on screen.
  Stream<void> get prompts => _client.prompts;

  @override
  Stream<RemoteState> get states => _states.stream;
  @override
  Stream<Object> get errors => const Stream.empty();
  @override
  Stream<void> get closed => _client.closed;
  @override
  RemoteState get state => _state;
  @override
  bool get isConnected => _client.isConnected;

  @override
  Set<String> get capabilities => {
    ..._shared.webosButtons.keys,
    ..._shared.webosRequests.keys,
    'tvpower',
    'text',
    'launch',
  };

  @override
  Future<void> connect() async {
    await _client.connect();
    _emit(_state.copyWith(powered: true));

    _client.subscribe('ssap://audio/getVolume', (payload) {
      final level = payload['volume'];
      _emit(
        _state.copyWith(
          volume: level is num ? level / 100 : null,
          muted: payload['muted'] as bool?,
        ),
      );
    });
    _client.subscribe(
      'ssap://com.webos.applicationManager/getForegroundAppInfo',
      (payload) =>
          _emit(_state.copyWith(currentApp: payload['appId'] as String?)),
    );
  }

  @override
  Future<void> close() => _client.close();

  @override
  Future<void> send(String command, [Object? arg]) async {
    switch (command) {
      // The set is being asked to switch itself off; there is no separate
      // "screen" to power down.
      case 'power' || 'tvpower':
        return _client.request('ssap://system/turnOff').then((_) {});
      case 'text':
        final socket = await _client.request(
          'ssap://com.webos.service.ime/registerRemoteKeyboard',
        );
        return socket.isEmpty ? null : null;
      case 'launch' || 'applink':
        await _client.request('ssap://system.launcher/launch', {'id': '$arg'});
        return;
      case 'input':
        await _client.request('ssap://tv/switchInput', {'inputId': '$arg'});
        return;
    }

    final uri = _shared.webosRequests[command];
    if (uri != null) {
      await _client.request(uri);
      return;
    }

    final button = _shared.webosButtons[command];
    if (button == null) throw UnsupportedCommand(command);
    return _client.button(button);
  }

  void _emit(RemoteState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}

/* ---------------- Samsung Tizen ---------------- */

class TizenSession implements DeviceSession {
  TizenSession({
    required this.device,
    required SharedData shared,
    String? token,
  }) : _shared = shared,
       _client = TizenClient(host: device.host, token: token);

  @override
  final Device device;

  final SharedData _shared;
  final TizenClient _client;

  final _states = StreamController<RemoteState>.broadcast();
  RemoteState _state = const RemoteState();

  /// Emits the token the television returns once its prompt is accepted.
  Stream<String> get tokens => _client.tokens;

  @override
  Stream<RemoteState> get states => _states.stream;
  @override
  Stream<Object> get errors => _client.errors;
  @override
  Stream<void> get closed => _client.closed;
  @override
  RemoteState get state => _state;
  @override
  bool get isConnected => _client.isConnected;

  @override
  Set<String> get capabilities => {..._shared.tizenKeys.keys, 'text', 'launch'};

  @override
  Future<void> connect() async {
    await _client.connect();
    // The set answers nothing about its own state, so being connected is the
    // only thing that can honestly be reported.
    _emit(_state.copyWith(powered: true));
  }

  @override
  Future<void> close() => _client.close();

  @override
  Future<void> send(String command, [Object? arg]) async {
    if (command == 'text') return _client.sendText('${arg ?? ''}');
    if (command == 'launch' || command == 'applink') {
      return _client.launch('$arg');
    }
    final key = _shared.tizenKeys[command];
    if (key == null) throw UnsupportedCommand(command);
    _client.sendKey(key);
  }

  void _emit(RemoteState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}

class UnsupportedCommand implements Exception {
  const UnsupportedCommand(this.command);
  final String command;
  @override
  String toString() => 'הפקודה $command אינה נתמכת במכשיר הזה';
}

/// The webOS registration manifest, loaded from the shared data.
Future<Map<String, dynamic>> loadWebosRegistration() async {
  final json = jsonDecode(
    await rootBundle.loadString('assets/shared/webos_pairing.json'),
  ) as Map<String, dynamic>;
  return {...json}..remove(r'$comment');
}
