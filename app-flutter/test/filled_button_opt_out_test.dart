import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Argument text of every `FilledButton.styleFrom(...)` call in [source]
/// (balanced parentheses, so nested `Size(...)` calls stay inside).
Iterable<String> styleFromCalls(String source) sync* {
  const marker = 'FilledButton.styleFrom(';
  var from = 0;
  while (true) {
    final start = source.indexOf(marker, from);
    if (start < 0) return;
    var depth = 1;
    var i = start + marker.length;
    while (depth > 0 && i < source.length) {
      final ch = source[i];
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      i++;
    }
    yield source.substring(start + marker.length, i - 1);
    from = i;
  }
}

void main() {
  test('styleFromCalls keeps nested calls inside one argument list', () {
    const src = 'a(FilledButton.styleFrom(minimumSize: const Size(1, 2), backgroundColor: x)); '
        'FilledButton.styleFrom(textStyle: t)';
    expect(styleFromCalls(src).toList(), [
      'minimumSize: const Size(1, 2), backgroundColor: x',
      'textStyle: t',
    ]);
  });

  test('every FilledButton with its own backgroundColor opts out of the brand gradient', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('app_theme.dart'));
    for (final file in files) {
      for (final args in styleFromCalls(file.readAsStringSync())) {
        if (args.contains('backgroundColor:') && !args.contains('backgroundBuilder:')) {
          offenders.add('${file.path}: ${args.replaceAll(RegExp(r'\s+'), ' ').trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'add backgroundBuilder: NwButtons.solid');
  });
}
