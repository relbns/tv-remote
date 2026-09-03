import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

/// A client certificate and its private key, both PEM encoded.
///
/// Android TV Remote v2 is mutual TLS: the box authenticates the *client*, so a
/// certificate has to exist before pairing can even start. It is generated on
/// the device, kept for the life of the pairing, and replayed on every later
/// connection — losing it means pairing again.
class ClientCertificate {
  const ClientCertificate({
    required this.privateKeyPem,
    required this.certificatePem,
  });

  final String privateKeyPem;
  final String certificatePem;

  Map<String, String> toJson() => {
    'key': privateKeyPem,
    'cert': certificatePem,
  };

  factory ClientCertificate.fromJson(Map<String, dynamic> json) =>
      ClientCertificate(
        privateKeyPem: json['key'] as String,
        certificatePem: json['cert'] as String,
      );
}

/// Build a fresh self-signed certificate for this installation.
///
/// The box never validates the subject — it only pins whatever certificate it
/// saw during pairing — so the fields exist to be well-formed, not to be
/// meaningful. [commonName] is what appears in the box's list of paired
/// devices, which is the one field a person will actually read.
ClientCertificate generateClientCertificate({
  String commonName = 'TV Remote',
  String organisation = 'tv-remote',
  String country = 'IL',
  int validityDays = 10000,
}) {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = pair.privateKey as RSAPrivateKey;
  final publicKey = pair.publicKey as RSAPublicKey;

  // A random serial keeps two installations from colliding on a box that keys
  // its paired-device list by serial.
  final serial = BigInt.from(Random.secure().nextInt(1 << 32)).abs();

  final csr = X509Utils.generateRsaCsrPem(
    {'CN': commonName, 'O': organisation, 'C': country},
    privateKey,
    publicKey,
  );

  final certificate = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csr,
    validityDays,
    serialNumber: serial.toString(),
  );

  return ClientCertificate(
    privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    certificatePem: certificate,
  );
}

/// The two numbers that make up an RSA public key, as the pairing digest needs
/// them: unsigned big-endian bytes, with the exponent left-padded to a whole
/// number of bytes.
class RsaPublicNumbers {
  const RsaPublicNumbers({required this.modulus, required this.exponent});

  final Uint8List modulus;
  final Uint8List exponent;
}

/// Read the public key out of a PEM certificate — ours, or the one the box
/// presents. `dart:io` exposes a peer certificate only as DER/PEM with no key
/// accessor, so the certificate has to be re-parsed to reach the numbers.
RsaPublicNumbers publicNumbersFromPem(String pem) {
  final data = X509Utils.x509CertificateFromPem(pem);
  final hex = data.tbsCertificate?.subjectPublicKeyInfo.bytes;
  if (hex == null)
    throw const FormatException('לתעודה אין SubjectPublicKeyInfo');

  final key = CryptoUtils.rsaPublicKeyFromDERBytes(_hexToBytes(hex));
  return RsaPublicNumbers(
    modulus: bigIntToBytes(key.modulus!),
    exponent: bigIntToBytes(key.exponent!),
  );
}

/// Unsigned big-endian bytes of [value], padded to a whole number of bytes.
///
/// This padding is the subtle part: the reference implementation reads the
/// exponent as the hex string "0x10001" and rebuilds it as "010001", so 65537
/// contributes three bytes to the digest, not two. Dropping the pad silently
/// produces a valid-looking digest that the box always rejects.
Uint8List bigIntToBytes(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  return _hexToBytes(hex);
}

Uint8List _hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  return Uint8List.fromList([
    for (var i = 0; i + 1 < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
