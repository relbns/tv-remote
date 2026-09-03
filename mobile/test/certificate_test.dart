import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/src/protocol/certificate.dart';

void main() {
  test('generates a certificate dart:io will accept for mutual TLS', () {
    final cert = generateClientCertificate(commonName: 'Test Remote');

    expect(cert.certificatePem, contains('BEGIN CERTIFICATE'));
    // basic_utils emits PKCS#8 ('BEGIN PRIVATE KEY'); older tooling emits
    // PKCS#1 ('BEGIN RSA PRIVATE KEY'). dart:io accepts either.
    expect(cert.privateKeyPem, contains('PRIVATE KEY'));

    // The real assertion: SecurityContext must take the pair straight from
    // memory. If this throws, run-time pairing is impossible on this platform
    // and the whole Android TV driver needs a different approach.
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(cert.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(cert.privateKeyPem));

    expect(context, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('each installation gets a distinct certificate', () {
    final a = generateClientCertificate();
    final b = generateClientCertificate();
    expect(a.certificatePem, isNot(equals(b.certificatePem)));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
