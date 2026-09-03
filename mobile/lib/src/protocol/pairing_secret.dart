import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'certificate.dart';

/// The pairing digest.
///
/// The box shows six hexadecimal characters. The first byte of that code is a
/// checksum; the remaining two bytes are mixed into a SHA-256 over both
/// certificates' public numbers. The box computes the same digest and compares,
/// which is what proves the person holding the remote can see the screen.
class PairingSecret {
  const PairingSecret._(this.digest, this.checksumMatches);

  /// The bytes to put in the PairingSecret message.
  final Uint8List digest;

  /// The digest as lowercase hex — the form used in tests and logs.
  String get hex =>
      digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Whether the digest agrees with the checksum byte in the code. A mismatch
  /// means the code was mistyped, and is worth catching before bothering the
  /// box — a rejected secret ends the whole pairing session.
  final bool checksumMatches;
}

/// Build the digest for [code] — six hex characters as displayed on the screen.
PairingSecret computePairingSecret({
  required String code,
  required String clientCertificatePem,
  required String serverCertificatePem,
}) {
  final normalised = code.trim().replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (normalised.length != 6) {
    throw const FormatException('הקוד חייב להיות שישה תווים הקסדצימליים');
  }

  final codeBytes = _hexToBytes(normalised);
  final client = publicNumbersFromPem(clientCertificatePem);
  final server = publicNumbersFromPem(serverCertificatePem);

  final input = BytesBuilder()
    ..add(client.modulus)
    ..add(client.exponent)
    ..add(server.modulus)
    ..add(server.exponent)
    // The leading checksum byte is excluded from the hash — only the two
    // bytes after it take part.
    ..add(codeBytes.sublist(1));

  final digest = Uint8List.fromList(sha256.convert(input.toBytes()).bytes);
  return PairingSecret._(digest, digest.first == codeBytes.first);
}

Uint8List _hexToBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
