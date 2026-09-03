import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../proto/pairingmessage.pb.dart';
import '../certificate.dart';
import '../pairing_secret.dart';
import 'framing.dart';

/// Pairing over port 6467.
///
/// The exchange is fixed: request → option → configuration, at which point the
/// box puts a six-character code on the screen. Whoever can read that code
/// proves they are in the room, and the digest built from it lets the box trust
/// this client's certificate from then on.
///
///     final pairing = AndroidTvPairing(host: '192.168.1.42', certificate: cert);
///     await pairing.begin();              // the code is now on the screen
///     await pairing.submitCode('A1B2C3'); // returns once the box accepts it
///     await pairing.close();
class AndroidTvPairing {
  AndroidTvPairing({
    required this.host,
    required this.certificate,
    this.port = 6467,
    this.serviceName = 'tv-remote',
    this.clientName = 'TV Remote',
    this.timeout = const Duration(seconds: 15),
  });

  final String host;
  final int port;
  final ClientCertificate certificate;
  final String serviceName;
  final String clientName;
  final Duration timeout;

  SecureSocket? _socket;
  final _decoder = DelimitedDecoder();
  String? _serverCertificatePem;

  Completer<void>? _codeReady;
  Completer<void>? _paired;

  /// Connect and drive the handshake until the box displays its code.
  Future<void> begin() async {
    final socket = await SecureSocket.connect(
      host,
      port,
      context: _securityContext(),
      // The box presents a self-signed certificate that cannot be replaced.
      // Its identity is established by the pairing code instead.
      onBadCertificate: (_) => true,
    ).timeout(timeout);

    _socket = socket;
    _serverCertificatePem = socket.peerCertificate?.pem;
    if (_serverCertificatePem == null) {
      await close();
      throw const AndroidTvPairingException('הממיר לא הציג תעודה');
    }

    _codeReady = Completer<void>();
    socket.listen(
      _onData,
      onError: _fail,
      onDone: () =>
          _fail(const AndroidTvPairingException('החיבור נסגר בטרם עת')),
      cancelOnError: true,
    );

    _send(
      PairingMessage(
        protocolVersion: 2,
        status: PairingMessage_Status.STATUS_OK,
        pairingRequest: PairingRequest(
          serviceName: serviceName,
          clientName: clientName,
        ),
      ),
    );

    return _codeReady!.future.timeout(timeout);
  }

  /// Submit the code from the screen. Resolves once the box accepts it.
  Future<void> submitCode(String code) {
    final socket = _socket;
    if (socket == null) {
      throw const AndroidTvPairingException('הצימוד לא הותחל');
    }

    final secret = computePairingSecret(
      code: code,
      clientCertificatePem: certificate.certificatePem,
      serverCertificatePem: _serverCertificatePem!,
    );

    // The box would simply drop the session on a wrong secret, leaving no way
    // to retry without starting over. The checksum byte catches a typo here.
    if (!secret.checksumMatches) {
      throw const AndroidTvPairingException(
        'הקוד שהוזן אינו תואם — בדוק את המסך',
      );
    }

    _paired = Completer<void>();
    _send(
      PairingMessage(
        protocolVersion: 2,
        status: PairingMessage_Status.STATUS_OK,
        pairingSecret: PairingSecret(secret: secret.digest),
      ),
    );
    return _paired!.future.timeout(timeout);
  }

  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  SecurityContext _securityContext() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificate.certificatePem))
    ..usePrivateKeyBytes(utf8.encode(certificate.privateKeyPem));

  void _send(PairingMessage message) =>
      _socket?.add(encodeDelimited(message.writeToBuffer()));

  void _onData(List<int> chunk) {
    for (final frame in _decoder.add(chunk)) {
      final PairingMessage message;
      try {
        message = PairingMessage.fromBuffer(frame);
      } on Exception catch (error) {
        _fail(AndroidTvPairingException('הודעה לא קריאה מהממיר: $error'));
        return;
      }

      if (message.status != PairingMessage_Status.STATUS_OK) {
        _fail(AndroidTvPairingException(_describe(message.status)));
        return;
      }

      if (message.hasPairingRequestAck()) {
        _send(
          PairingMessage(
            protocolVersion: 2,
            status: PairingMessage_Status.STATUS_OK,
            pairingOption: PairingOption(
              preferredRole: RoleType.ROLE_TYPE_INPUT,
              inputEncodings: [
                PairingEncoding(
                  type: PairingEncoding_EncodingType.ENCODING_TYPE_HEXADECIMAL,
                  symbolLength: 6,
                ),
              ],
            ),
          ),
        );
      } else if (message.hasPairingOption()) {
        _send(
          PairingMessage(
            protocolVersion: 2,
            status: PairingMessage_Status.STATUS_OK,
            pairingConfiguration: PairingConfiguration(
              clientRole: RoleType.ROLE_TYPE_INPUT,
              encoding: PairingEncoding(
                type: PairingEncoding_EncodingType.ENCODING_TYPE_HEXADECIMAL,
                symbolLength: 6,
              ),
            ),
          ),
        );
      } else if (message.hasPairingConfigurationAck()) {
        // The code is on the screen from this moment.
        if (_codeReady?.isCompleted == false) {
          _codeReady!.complete();
        }
      } else if (message.hasPairingSecretAck()) {
        if (_paired?.isCompleted == false) {
          _paired!.complete();
        }
      }
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    final failure = error is AndroidTvPairingException
        ? error
        : AndroidTvPairingException(error.toString());
    for (final completer in [_codeReady, _paired]) {
      if (completer != null && !completer.isCompleted) {
        completer.completeError(failure, stack);
      }
    }
    unawaited(close());
  }

  static String _describe(PairingMessage_Status status) => switch (status) {
    PairingMessage_Status.STATUS_BAD_CONFIGURATION =>
      'הממיר דחה את הגדרות הצימוד',
    PairingMessage_Status.STATUS_BAD_SECRET =>
      'הקוד שגוי — נסה שוב עם הקוד שמופיע כעת על המסך',
    _ => 'הצימוד נכשל (סטטוס ${status.value})',
  };
}

class AndroidTvPairingException implements Exception {
  const AndroidTvPairingException(this.message);
  final String message;
  @override
  String toString() => message;
}
