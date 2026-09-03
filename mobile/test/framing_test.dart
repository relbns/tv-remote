import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/src/protocol/androidtv/framing.dart';

void main() {
  test('round-trips a short message', () {
    final body = Uint8List.fromList([1, 2, 3]);
    final decoded = DelimitedDecoder().add(encodeDelimited(body));
    expect(decoded, [body]);
  });

  test('handles a message longer than one varint byte', () {
    // 300 bytes needs a two-byte prefix — exactly where the reference
    // implementation's single-byte read would fail.
    final body = Uint8List.fromList(List.generate(300, (i) => i % 256));
    final framed = encodeDelimited(body);
    expect(framed.length, 302);
    expect(DelimitedDecoder().add(framed), [body]);
  });

  test('reassembles a message split across chunks', () {
    final body = Uint8List.fromList(List.generate(200, (i) => i % 256));
    final framed = encodeDelimited(body);
    final decoder = DelimitedDecoder();

    expect(decoder.add(framed.sublist(0, 1)), isEmpty);
    expect(decoder.add(framed.sublist(1, 50)), isEmpty);
    expect(decoder.add(framed.sublist(50)), [body]);
  });

  test('splits several messages arriving in one chunk', () {
    final a = Uint8List.fromList([1, 2]);
    final b = Uint8List.fromList([3, 4, 5]);
    final combined = [...encodeDelimited(a), ...encodeDelimited(b)];
    expect(DelimitedDecoder().add(combined), [a, b]);
  });
}
