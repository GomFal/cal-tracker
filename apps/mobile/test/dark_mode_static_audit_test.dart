import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI feature code uses theme palettes instead of light-only colors', () {
    final root = Directory('lib/ui');
    final violations = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('core/design_system.dart')) continue;
      // Camera overlay screens use absolute white/black for contrast over
      // the live camera preview (not theme-controlled).
      if (entity.path.endsWith('usual_food_scan_screen.dart') ||
          entity.path.endsWith('scan_viewfinder_overlay.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      final hasFreshColors = source.contains('FreshColors.');
      final hasHardWhiteOrBlack =
          source.contains('Colors.white') || source.contains('Colors.black');
      if (hasFreshColors || hasHardWhiteOrBlack) {
        violations.add(entity.path);
      }
    }

    expect(violations, isEmpty);
  });
}
