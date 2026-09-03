import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// LG webOS over SSAP.
///
/// The set speaks JSON over a WebSocket on 3001. The first connection makes it
/// show an on-screen prompt; accepting returns a client key that is replayed on
/// every later connection, so the prompt appears exactly once.
///
/// Two channels are involved: ordinary commands are request/response over the
/// main socket, while the buttons a remote has — arrows, back, home — travel on
/// a separate "pointer input" socket the set hands out on request.
class WebosClient {
  WebosClient({
    required this.host,
    required this.registration,
    this.clientKey,
    this.securePort = 3001,
    this.plainPort = 3000,
    this.timeout = const Duration(seconds: 12),
  });

  final String host;

  /// TLS port used by current sets.
  final int securePort;

  /// Plain WebSocket port. Older sets keep 3001 open but answer it without TLS,
  /// so a failed handshake there is a signal to fall back, not an error.
  final int plainPort;

  /// The endpoint that actually worked, once connected.
  String? connectedUrl;

  /// The registration manifest, loaded from shared/webos_pairing.json.
  final Map<String, dynamic> registration;

  /// Returned by the set after the prompt is accepted; null on first contact.
  String? clientKey;

  final Duration timeout;

  WebSocket? _socket;
  WebSocket? _pointer;
  int _nextId = 1;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _subscriptions = <String, void Function(Map<String, dynamic>)>{};

  final _keys = StreamController<String>.broadcast();
  final _prompts = StreamController<void>.broadcast();

  /// Emits the client key once the set issues one — store it.
  Stream<String> get clientKeys => _keys.stream;

  /// Emits when the set puts its confirmation prompt on screen.
  Stream<void> get prompts => _prompts.stream;

  bool get isConnected => _socket != null;

  Future<void> connect() async {
    await close();

    // The set presents a self-signed certificate it will not let you replace,
    // so chain validation is off; the connection never leaves the LAN.
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (_, _, _) => true;

    final socket = await _openSocket(client);
    _socket = socket;

    socket.listen(
      _onMessage,
      onDone: _onClosed,
      onError: (Object _) => _onClosed(),
    );

    await _register();
  }

  /// Try TLS first, then plain. Only a handshake failure justifies the retry —
  /// anything else is a real problem and is reported as-is.
  Future<WebSocket> _openSocket(HttpClient client) async {
    try {
      final url = 'wss://$host:$securePort';
      final socket = await WebSocket.connect(
        url,
        customClient: client,
      ).timeout(timeout);
      connectedUrl = url;
      return socket;
    } on HandshakeException {
      final url = 'ws://$host:$plainPort';
      final socket = await WebSocket.connect(url).timeout(timeout);
      connectedUrl = url;
      return socket;
    }
  }

  Future<void> _register() async {
    final registered = Completer<void>();
    final id = _send({
      'type': 'register',
      'payload': {'client-key': ?clientKey, ...registration},
    });

    // Registration answers twice: first PROMPT while the set waits for the
    // person, then registered with the key. Only the second one completes.
    _subscriptions[id] = (message) {
      final type = message['type'];
      final payload = message['payload'] as Map<String, dynamic>? ?? const {};

      if (type == 'response' && payload['pairingType'] == 'PROMPT') {
        if (!_prompts.isClosed) _prompts.add(null);
      } else if (type == 'registered') {
        final key = payload['client-key'] as String?;
        if (key != null && key != clientKey) {
          clientKey = key;
          if (!_keys.isClosed) _keys.add(key);
        }
        _subscriptions.remove(id);
        if (!registered.isCompleted) registered.complete();
      } else if (type == 'error') {
        _subscriptions.remove(id);
        if (!registered.isCompleted) {
          registered.completeError(
            WebosException(message['error']?.toString() ?? 'הרישום נדחה'),
          );
        }
      }
    };

    // No timeout here: the set is waiting for a person to pick up the remote
    // and accept, which takes as long as it takes.
    return registered.future;
  }

  /// Send an SSAP request and wait for its reply.
  Future<Map<String, dynamic>> request(
    String uri, [
    Map<String, dynamic>? payload,
  ]) {
    final completer = Completer<Map<String, dynamic>>();
    final id = _send({'type': 'request', 'uri': uri, 'payload': ?payload});
    _pending[id] = completer;
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw WebosException('אין תשובה מהטלוויזיה על $uri');
      },
    );
  }

  /// Subscribe to a value the set pushes on change, e.g. volume.
  void subscribe(String uri, void Function(Map<String, dynamic>) onValue) {
    final id = _send({'type': 'subscribe', 'uri': uri});
    _subscriptions[id] = (message) {
      final payload = message['payload'] as Map<String, dynamic>?;
      if (payload != null) {
        onValue(payload);
      }
    };
  }

  /// Press one of the physical remote's buttons, e.g. `UP`, `ENTER`, `BACK`.
  Future<void> button(String name) async {
    final pointer = await _pointerSocket();
    pointer.add('type:button\nname:$name\n\n');
  }

  Future<WebSocket> _pointerSocket() async {
    final existing = _pointer;
    if (existing != null) return existing;

    final response = await request(
      'ssap://com.webos.service.networkinput/getPointerInputSocket',
    );
    final uri = response['socketPath'] as String?;
    if (uri == null) {
      throw const WebosException('הטלוויזיה לא סיפקה ערוץ כפתורים');
    }

    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    final socket = await WebSocket.connect(
      uri,
      customClient: client,
    ).timeout(timeout);
    _pointer = socket;
    socket.listen(
      (_) {},
      onDone: () => _pointer = null,
      onError: (Object _) => _pointer = null,
    );
    return socket;
  }

  String _send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket == null) throw const WebosException('אין חיבור לטלוויזיה');
    final id = '${_nextId++}';
    socket.add(jsonEncode({'id': id, ...message}));
    return id;
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } on Object {
      return;
    }

    final id = message['id'] as String?;
    if (id == null) return;

    final subscription = _subscriptions[id];
    if (subscription != null) {
      subscription(message);
      return;
    }

    final pending = _pending.remove(id);
    if (pending == null) return;

    if (message['type'] == 'error') {
      pending.completeError(
        WebosException(message['error']?.toString() ?? 'שגיאה'),
      );
    } else {
      pending.complete(message['payload'] as Map<String, dynamic>? ?? const {});
    }
  }

  void _onClosed() {
    _socket = null;
    _pointer = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(const WebosException('החיבור לטלוויזיה נסגר'));
      }
    }
    _pending.clear();
    _subscriptions.clear();
  }

  Future<void> close() async {
    final socket = _socket;
    final pointer = _pointer;
    _socket = null;
    _pointer = null;
    await pointer?.close();
    await socket?.close();
  }

  Future<void> dispose() async {
    await close();
    await _keys.close();
    await _prompts.close();
  }
}

class WebosException implements Exception {
  const WebosException(this.message);
  final String message;
  @override
  String toString() => message;
}
