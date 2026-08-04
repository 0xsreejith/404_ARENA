import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards Epic 7: production (non-lobby_ui) sources must not import DemoData.
void main() {
  test('production feature paths do not import lobby_ui/demo_data.dart', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue);

    final offenders = <String>[];
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('${Platform.pathSeparator}lobby_ui${Platform.pathSeparator}')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (source.contains('lobby_ui/demo_data.dart') || source.contains('DemoData')) {
        // Allow comments that mention DemoData as a forbidden pattern.
        final importsDemo = source.contains("import 'package:arena_os/features/lobby_ui/demo_data.dart'");
        if (importsDemo) offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty, reason: 'DemoData imported outside lobby_ui:\n${offenders.join('\n')}');
  });
}
