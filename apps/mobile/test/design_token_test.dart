import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Design-token gate (FRONTEND-1 / Band 2 consolidation).
///
/// The palette lives in `AppColors` and the radius scale in `AppShapes`. Both
/// are useless if feature code can keep re-spelling `Color(0xFF...)` and
/// `BorderRadius.circular(12)` inline, so this test fails the build the moment
/// a raw literal reappears outside the token layer.
void main() {
  Iterable<File> dartFiles() sync* {
    final lib = Directory('lib');
    yield* lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') &&
            !f.path.startsWith('lib${Platform.pathSeparator}core${Platform.pathSeparator}theme${Platform.pathSeparator}'));
  }

  test('no raw radius literals outside the shape tokens', () {
    final radius = RegExp(r'(?:Border)?Radius\.circular\(\s*\d');
    final offenders = <String>[];

    for (final file in dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (radius.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Use AppShapes tokens instead of raw radius literals:\n'
            '${offenders.join('\n')}');
  });

  test('no raw color literals outside the palette tokens', () {
    final color = RegExp(r'Color\(0x[0-9A-Fa-f]+\)');
    final offenders = <String>[];

    for (final file in dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (color.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Use AppColors tokens instead of raw color literals:\n'
            '${offenders.join('\n')}');
  });
}
