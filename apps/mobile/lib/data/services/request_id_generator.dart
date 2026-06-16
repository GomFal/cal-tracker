import 'dart:math' as math;

/// Generates RFC 4122 v4 style identifiers without bringing in new
/// dependencies. The output is suitable for the `X-Request-Id` HTTP
/// header and for telemetry trace ids.
class RequestIdGenerator {
  RequestIdGenerator({math.Random? random})
    : _random = random ?? math.Random();

  final math.Random _random;

  String next() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
