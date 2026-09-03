import 'dart:typed_data';

/// Length-delimited protobuf framing, as Android TV Remote v2 uses on the wire:
/// every message is preceded by its length as a base-128 varint.
///
/// The reference JavaScript implementation reads the prefix as a single byte,
/// which holds only while messages stay under 128 bytes. A long app link or a
/// long string of injected text crosses that line, so the varint is decoded
/// properly here.

Uint8List encodeDelimited(List<int> message) {
  final prefix = <int>[];
  var length = message.length;
  while (length >= 0x80) {
    prefix.add((length & 0x7F) | 0x80);
    length >>= 7;
  }
  prefix.add(length);
  return Uint8List.fromList([...prefix, ...message]);
}

/// Reassembles whole messages from a byte stream that splits and coalesces them
/// arbitrarily.
class DelimitedDecoder {
  Uint8List _buffer = Uint8List(0);

  /// Feed received bytes; returns every complete message now available.
  List<Uint8List> add(List<int> chunk) {
    _buffer = Uint8List.fromList([..._buffer, ...chunk]);

    final messages = <Uint8List>[];
    var offset = 0;

    while (offset < _buffer.length) {
      final header = _readVarint(offset);
      if (header == null) break; // length prefix not fully arrived

      final (length, headerSize) = header;
      final end = offset + headerSize + length;
      if (end > _buffer.length) break; // body not fully arrived

      messages.add(
        Uint8List.fromList(_buffer.sublist(offset + headerSize, end)),
      );
      offset = end;
    }

    // Copy rather than take a view: a view would pin the whole original buffer
    // in memory for the lifetime of the connection.
    if (offset > 0) _buffer = Uint8List.fromList(_buffer.sublist(offset));
    return messages;
  }

  /// Returns (value, bytesConsumed), or null when the varint is incomplete.
  (int, int)? _readVarint(int offset) {
    var value = 0;
    var shift = 0;
    var index = offset;

    while (index < _buffer.length) {
      final byte = _buffer[index];
      value |= (byte & 0x7F) << shift;
      index++;
      if (byte & 0x80 == 0) return (value, index - offset);
      shift += 7;
      if (shift > 35) throw const FormatException('varint פגום');
    }
    return null;
  }
}
