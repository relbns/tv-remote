import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/src/protocol/pairing_secret.dart';

import 'fixtures/load.dart';

void main() {
  // Frozen after a byte-for-byte comparison against the Node reference
  // implementation, which is known to work against real hardware.
  const expected =
      '5722852b808f7e24daa502a433c7f39603d81e94bb9f936e529b3f89298512cc';

  late String client;
  late String server;

  setUpAll(() {
    client = loadFixture('client.pem');
    server = loadFixture('server.pem');
  });

  test('digest matches the reference implementation', () {
    final secret = computePairingSecret(
      code: 'A1B2C3',
      clientCertificatePem: client,
      serverCertificatePem: server,
    );
    expect(secret.hex, expected);
  });

  test('a mistyped code is caught by the checksum byte', () {
    final good = computePairingSecret(
      code: 'A1B2C3',
      clientCertificatePem: client,
      serverCertificatePem: server,
    );
    final bad = computePairingSecret(
      code: 'FFB2C3', // same payload, wrong checksum byte
      clientCertificatePem: client,
      serverCertificatePem: server,
    );
    expect(
      good.digest,
      equals(bad.digest),
      reason: 'הבייט הראשון אינו נכנס לגיבוב',
    );
    expect(bad.checksumMatches, isFalse);
  });

  test('rejects codes that are not six hex characters', () {
    expect(
      () => computePairingSecret(
        code: 'ABC',
        clientCertificatePem: client,
        serverCertificatePem: server,
      ),
      throwsFormatException,
    );
  });
}
