import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Samsung Tizen (2016 and later) — JSON over a WebSocket on 8002.
///
/// On the first connection the television shows an "allow this device?" prompt
/// and, once accepted, returns a token in its `ms.channel.connect` frame. The
/// token is replayed on every later connection, so the prompt appears once.
///
/// The set presents a self-signed certificate it will not let you replace, so
/// chain validation is turned off. The connection never leaves the home network.
class TizenClient {
  TizenClient({
    required this.host,
    this.token,
    this.name = 'Orbit',
    this.port = 8002,
    this.timeout = const Duration(seconds: 10),
  });

  final String host;
  final int port;
  final String name;
  final Duration timeout;

  /// Returned by the television after the prompt is accepted; null on first
  /// contact, which is what makes the prompt appear.
  String? token;

  WebSocket? _socket;

  final _tokens = StreamController<String>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _closed = StreamController<void>.broadcast();

  /// Emits once when the television hands back a fresh token to store.
  Stream<String> get tokens => _tokens.stream;
  Stream<Object> get errors => _errors.stream;
  Stream<void> get closed => _closed.stream;

  bool get isConnected => _socket != null;

  static String _b64(String value) => base64.encode(utf8.encode(value));

  /// The unauthenticated info endpoint — also the cheapest liveness check, and
  /// the only way to learn the MAC address needed to wake the set later.
  static Future<TizenInfo?> fetchInfo(
    String host, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(
        Uri.parse('http://$host:8001/api/v2/'),
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(
        await response.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      final device = json['device'] as Map<String, dynamic>? ?? const {};
      return TizenInfo(
        name: device['name'] as String?,
        model: device['modelName'] as String?,
        mac: device['wifiMac'] as String?,
        powered: switch (device['PowerState']) {
          'on' => true,
          final String _ => false,
          _ => null,
        },
      );
    } on Object {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> connect() async {
    await close();

    final query = <String, String>{
      'name': _b64(name),
      if (token != null && token!.isNotEmpty) 'token': token!,
    };
    final uri = Uri(
      scheme: 'wss',
      host: host,
      port: port,
      path: '/api/v2/channels/samsung.remote.control',
      queryParameters: query,
    );

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (_, _, _) => true;

    final socket = await WebSocket.connect(
      uri.toString(),
      customClient: client,
    ).timeout(timeout);
    _socket = socket;

    socket.listen(
      _onMessage,
      onDone: () {
        _socket = null;
        if (!_closed.isClosed) _closed.add(null);
      },
      onError: (Object error) {
        if (!_errors.isClosed) _errors.add(error);
      },
      cancelOnError: false,
    );
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode('$raw') as Map<String, dynamic>;
    } on Object {
      return;
    }

    switch (message['event']) {
      case 'ms.channel.connect':
        final fresh = (message['data'] as Map?)?['token'];
        if (fresh != null && '$fresh' != token) {
          token = '$fresh';
          if (!_tokens.isClosed) _tokens.add(token!);
        }
      case 'ms.channel.unauthorized':
        if (!_errors.isClosed) {
          _errors.add(
            const TizenException(
              'הטלוויזיה דחתה את הבקשה — יש לאשר את המכשיר על המסך',
            ),
          );
        }
    }
  }

  void _send(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) throw const TizenException('הטלוויזיה אינה מחוברת');
    try {
      socket.add(jsonEncode(payload));
    } on Object catch (failure) {
      // A socket the television reset asynchronously throws on write; letting
      // it escape would take down the zone rather than the one command.
      throw TizenException('$failure');
    }
  }

  /// Press a remote key, by the name in the shared table (e.g. KEY_VOLUP).
  void sendKey(String key) => _send({
    'method': 'ms.remote.control',
    'params': {
      'Cmd': 'Click',
      'DataOfCmd': key,
      'Option': 'false',
      'TypeOfRemote': 'SendRemoteKey',
    },
  });

  void sendText(String text) => _send({
    'method': 'ms.remote.control',
    'params': {
      'Cmd': _b64(text),
      'DataOfCmd': 'base64',
      'TypeOfRemote': 'SendInputString',
    },
  });

  void launch(String appId) => _send({
    'method': 'ms.channel.emit',
    'params': {
      'event': 'ed.apps.launch',
      'to': 'host',
      'data': {'appId': appId, 'action_type': 'DEEP_LINK'},
    },
  });

  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    try {
      await socket?.close();
    } on Object {
      // Already gone.
    }
  }

  Future<void> dispose() async {
    await close();
    await _tokens.close();
    await _errors.close();
    await _closed.close();
  }
}

class TizenInfo {
  const TizenInfo({this.name, this.model, this.mac, this.powered});
  final String? name;
  final String? model;
  final String? mac;
  final bool? powered;
}

class TizenException implements Exception {
  const TizenException(this.message);
  final String message;
  @override
  String toString() => message;
}
