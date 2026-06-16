import 'dart:math' as math;

import 'package:cal_tracker_mobile/data/services/request_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestIdGenerator', () {
    test('returns RFC 4122 v4 identifiers', () {
      final generator = RequestIdGenerator();
      final id = generator.next();
      expect(id.length, 36);
      // Version 4 marker: 13th hex digit is '4'.
      expect(id[14], '4');
      // Variant 10 marker: 17th hex digit is one of 8/9/a/b.
      expect(
        RegExp(r'[89ab]').hasMatch(id[19]),
        isTrue,
        reason: 'Expected variant 10 marker in id $id',
      );
    });

    test('produces unique ids across calls', () {
      final generator = RequestIdGenerator();
      final ids = List.generate(64, (_) => generator.next());
      expect(ids.toSet().length, ids.length);
    });

    test('honors injected randomness for deterministic tests', () {
      final first = RequestIdGenerator(
        random: math.Random(0xC0FFEE),
      ).next();
      final second = RequestIdGenerator(
        random: math.Random(0xC0FFEE),
      ).next();
      // Sanity check: two generators with the same seed produce the same
      // first id, which keeps logging, trace continuity, and tests stable.
      expect(first, second);
    });
  });
}
