library;

import 'dart:convert';
import 'dart:typed_data';

/// Encodes a DNS-SD TXT record (stub: Web non supporta Bonjour).
Uint8List encodeTxtRecord(Map<String, Uint8List> txt) {
  final builder = BytesBuilder(copy: false);
  for (final entry in txt.entries) {
    final keyBytes = ascii.encode(entry.key);
    final segmentLength = keyBytes.length + 1 + entry.value.length;
    if (segmentLength > 255) {
      throw ArgumentError(
        'TXT segment for "${entry.key}" is $segmentLength bytes; DNS-SD allows at most 255',
      );
    }
    builder.addByte(segmentLength);
    builder.add(keyBytes);
    builder.addByte(0x3d);
    builder.add(entry.value);
  }
  return builder.toBytes();
}

/// Stub: non disponibile su Web.
int toNetworkByteOrder(int port) => ((port & 0xff) << 8) | ((port >> 8) & 0xff);

abstract class BonjourApi {
  bool get isAvailable;

  Object register({
    required String name,
    required String type,
    required int port,
    required Uint8List txtRecord,
  });

  void deallocate(Object handle);
}

class BonjourException implements Exception {
  final String message;

  BonjourException(this.message);

  @override
  String toString() => 'BonjourException: $message';
}

/// Stub per Web: Bonjour non disponibile.
class RealBonjourApi implements BonjourApi {
  @override
  bool get isAvailable => false;

  @override
  Object register({
    required String name,
    required String type,
    required int port,
    required Uint8List txtRecord,
  }) {
    throw UnsupportedError('Bonjour is not available on this platform');
  }

  @override
  void deallocate(Object handle) {}
}
