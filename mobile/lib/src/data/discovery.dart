import 'dart:async';
import 'dart:io';

import 'device.dart';

/// A device found on the network but not yet added.
class Discovered {
  const Discovered({required this.kind, required this.host});
  final DeviceKind kind;
  final String host;
}

/// Finds devices by probing the control port each platform listens on.
///
/// mDNS would be tidier, but on Android receiving multicast needs a
/// `MulticastLock` that the Dart package does not take, so it fails silently on
/// exactly the devices this app runs on. A sweep of the local /24 needs no
/// permission beyond ordinary networking and finds a screen that was asleep
/// when it would not have been advertising anyway.
class Discovery {
  static const _ports = {
    6466: DeviceKind.androidtv,
    3001: DeviceKind.webos,
    8002: DeviceKind.tizen,
  };

  /// Probing 32 addresses at a time covers a /24 in a few seconds without
  /// exhausting the socket budget on a phone.
  static const _concurrency = 32;
  static const _probeTimeout = Duration(milliseconds: 900);

  /// Sweep every IPv4 /24 this device is on. Results arrive as they are found.
  static Stream<Discovered> sweep() async* {
    final controller = StreamController<Discovered>();
    final targets = await _targets();
    final queue = List.of(targets);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final host = queue.removeAt(0);
        for (final entry in _ports.entries) {
          if (!await _isOpen(host, entry.key)) continue;
          if (entry.value == DeviceKind.webos && !await _isWebos(host)) {
            continue; // port was open, but nothing behind it is a television
          }
          controller.add(Discovered(kind: entry.value, host: host));
          break; // one device, one kind
        }
      }
    }

    unawaited(
      Future.wait([for (var i = 0; i < _concurrency; i++) worker()])
          .whenComplete(controller.close),
    );

    yield* controller.stream;
  }

  static Future<List<String>> _targets() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    final hosts = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final parts = address.address.split('.');
        if (parts.length != 4) continue;
        final prefix = parts.take(3).join('.');
        for (var last = 1; last < 255; last++) {
          final host = '$prefix.$last';
          if (host != address.address && !hosts.contains(host)) hosts.add(host);
        }
      }
    }
    return hosts;
  }

  static Future<bool> _isOpen(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: _probeTimeout);
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  /// An open port is not an identification.
  ///
  /// Ports 3000 and 3001 are among the most common in use — a Node server on
  /// the same network was being offered as a television. A real webOS set
  /// answers 3001 with TLS and presents a certificate issued to LG, which is
  /// cheap to check and cannot be confused with an ordinary web server.
  static Future<bool> _isWebos(String host) async {
    try {
      final socket = await SecureSocket.connect(
        host,
        3001,
        timeout: _probeTimeout,
        onBadCertificate: (_) => true,
      );
      final subject = socket.peerCertificate?.subject ?? '';
      socket.destroy();
      return subject.toUpperCase().contains('LG ELECTRONICS');
    } on Object {
      return false;
    }
  }
}
