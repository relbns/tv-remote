import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../proto/remotemessage.pb.dart';
import '../certificate.dart';
import 'framing.dart';

/// State the box reports about itself while a session is open.
class RemoteState {
  const RemoteState({this.powered, this.volume, this.muted, this.currentApp});

  final bool? powered;

  /// 0..1, or null when the box has not reported a level yet.
  final double? volume;
  final bool? muted;

  /// Foreground package name, e.g. `com.netflix.ninja`.
  final String? currentApp;

  RemoteState copyWith({
    bool? powered,
    double? volume,
    bool? muted,
    String? currentApp,
  }) => RemoteState(
    powered: powered ?? this.powered,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    currentApp: currentApp ?? this.currentApp,
  );
}

/// A control session on port 6466, opened with the certificate pairing produced.
///
/// The box drives the start of the conversation: it asks for configuration,
/// then pings periodically. Missing a ping ends the session, so the reply is
/// not optional bookkeeping — it is what keeps the remote alive.
class AndroidTvRemote {
  AndroidTvRemote({
    required this.host,
    required this.certificate,
    this.port = 6466,
    this.model = 'TV Remote',
    this.vendor = 'tv-remote',
    this.timeout = const Duration(seconds: 15),
  });

  final String host;
  final int port;
  final ClientCertificate certificate;
  final String model;
  final String vendor;
  final Duration timeout;

  SecureSocket? _socket;
  final _decoder = DelimitedDecoder();
  final _states = StreamController<RemoteState>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _closed = StreamController<void>.broadcast();

  Completer<void>? _ready;
  RemoteState _state = const RemoteState();
  int _imeCounter = 0;
  int _fieldCounter = 0;

  /// Every state change the box reports.
  Stream<RemoteState> get states => _states.stream;

  /// Protocol errors that do not end the session.
  Stream<Object> get errors => _errors.stream;

  /// Fires when the session ends, for any reason — the phone slept, the box
  /// powered down, the network moved. Without it the UI keeps showing a live
  /// connection over a dead socket.
  Stream<void> get closed => _closed.stream;

  RemoteState get state => _state;
  bool get isConnected => _socket != null;

  /// Connect and wait until the box has accepted the configuration.
  Future<void> connect() async {
    if (_socket != null) await close();

    final socket = await SecureSocket.connect(
      host,
      port,
      context: SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(utf8.encode(certificate.certificatePem))
        ..usePrivateKeyBytes(utf8.encode(certificate.privateKeyPem)),
      // Identity was established during pairing; the box's certificate is
      // self-signed and cannot be validated against a public root.
      onBadCertificate: (_) => true,
    ).timeout(timeout);

    _socket = socket;
    _ready = Completer<void>();

    socket.listen(
      _onData,
      onError: (Object error) {
        _errors.add(error);
        _finishUnready(error);
      },
      onDone: () => _finishUnready(const RemoteException('החיבור נסגר')),
      cancelOnError: true,
    );

    return _ready!.future.timeout(timeout);
  }

  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  Future<void> dispose() async {
    await close();
    await _states.close();
    await _errors.close();
    await _closed.close();
  }

  /// Press a key. [keyCode] is an Android `KeyEvent` constant.
  void sendKey(
    int keyCode, {
    RemoteDirection direction = RemoteDirection.SHORT,
  }) {
    _send(
      RemoteMessage(
        remoteKeyInject: RemoteKeyInject(
          keyCode: RemoteKeyCode.valueOf(keyCode),
          direction: direction,
        ),
      ),
    );
  }

  /// Replace the contents of the focused text field.
  ///
  /// Injecting the whole string at once is why searching from the phone is
  /// bearable — the alternative is walking an on-screen keyboard per character.
  void sendText(String text) {
    final cursor = text.length;
    _send(
      RemoteMessage(
        remoteImeBatchEdit: RemoteImeBatchEdit(
          imeCounter: _imeCounter,
          fieldCounter: _fieldCounter,
          editInfo: [
            RemoteEditInfo(
              insert: 1,
              // RemoteEditInfo carries a RemoteImeObject here; the similarly
              // named RemoteTextFieldStatus belongs to a different message.
              textFieldStatus: RemoteImeObject(
                start: cursor,
                end: cursor,
                value: text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Launch an app by deep link, or by `intent:#Intent;package=...;end`.
  void sendAppLink(String link) {
    _send(
      RemoteMessage(
        remoteAppLinkLaunchRequest: RemoteAppLinkLaunchRequest(appLink: link),
      ),
    );
  }

  void _send(RemoteMessage message) {
    final socket = _socket;
    if (socket == null) throw const RemoteException('אין חיבור פעיל');
    try {
      socket.add(encodeDelimited(message.writeToBuffer()));
    } on Object catch (error) {
      // A write to a socket the box has just reset throws from outside any
      // await, so without this it escapes as an unhandled exception and takes
      // the zone with it. The session is over either way; report and close.
      _errors.add(error);
      _finishUnready(error);
    }
  }

  void _onData(List<int> chunk) {
    for (final frame in _decoder.add(chunk)) {
      final RemoteMessage message;
      try {
        message = RemoteMessage.fromBuffer(frame);
      } on Exception catch (error) {
        _errors.add(RemoteException('הודעה לא קריאה: $error'));
        continue;
      }
      _handle(message);
    }
  }

  void _handle(RemoteMessage message) {
    if (message.hasRemoteConfigure()) {
      _send(
        RemoteMessage(
          remoteConfigure: RemoteConfigure(
            code1: 622,
            deviceInfo: RemoteDeviceInfo(
              model: model,
              vendor: vendor,
              unknown1: 1,
              unknown2: '1',
              packageName: 'tv-remote',
              appVersion: '1.0.0',
            ),
          ),
        ),
      );
      if (_ready?.isCompleted == false) _ready!.complete();
    } else if (message.hasRemoteSetActive()) {
      _send(RemoteMessage(remoteSetActive: RemoteSetActive(active: 622)));
    } else if (message.hasRemotePingRequest()) {
      // Answering keeps the session alive; silence ends it.
      _send(
        RemoteMessage(
          remotePingResponse: RemotePingResponse(
            val1: message.remotePingRequest.val1,
          ),
        ),
      );
    } else if (message.hasRemoteImeKeyInject()) {
      _emit(
        _state.copyWith(
          currentApp: message.remoteImeKeyInject.appInfo.appPackage,
        ),
      );
    } else if (message.hasRemoteImeBatchEdit()) {
      // The box owns these counters. Text injected with stale values is
      // silently dropped, so the latest pair is kept for the next sendText.
      _imeCounter = message.remoteImeBatchEdit.imeCounter;
      _fieldCounter = message.remoteImeBatchEdit.fieldCounter;
    } else if (message.hasRemoteStart()) {
      _emit(_state.copyWith(powered: message.remoteStart.started));
    } else if (message.hasRemoteSetVolumeLevel()) {
      final level = message.remoteSetVolumeLevel;
      _emit(
        _state.copyWith(
          volume: level.volumeMax > 0
              ? level.volumeLevel / level.volumeMax
              : null,
          muted: level.volumeMuted,
        ),
      );
    }
  }

  void _emit(RemoteState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _finishUnready(Object error) {
    if (_ready?.isCompleted == false) _ready!.completeError(error);
    final wasConnected = _socket != null;
    _socket = null;
    if (wasConnected && !_closed.isClosed) _closed.add(null);
  }
}

class RemoteException implements Exception {
  const RemoteException(this.message);
  final String message;
  @override
  String toString() => message;
}
