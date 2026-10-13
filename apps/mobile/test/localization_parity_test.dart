import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicklers_warriors/core/l10n/app_localizations.dart';

AppLocalizations l10n(String code) =>
    AppLocalizations(Locale(code));

/// Keys built at runtime (for example `clinic.status.${_statusKey(code)}`) are
/// checked against the table directly in the widget tests; this suite covers
/// only the static literals, which is where a missing translation hides.
final RegExp _staticTrCall = RegExp(r"tr\(\s*'([^']+)'");

Set<String> _staticKeysUsedInLib() {
  final keys = <String>{};
  for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    if (file.path.endsWith('app_localizations.dart')) continue;
    for (final match in _staticTrCall.allMatches(file.readAsStringSync())) {
      final key = match.group(1)!;
      if (!key.contains(r'${')) keys.add(key);
    }
  }
  return keys;
}

void main() {
  final en = l10n('en').table;
  final sw = l10n('sw').table;

  test('English and Kiswahili tables expose exactly the same keys', () {
    expect(en.keys.toSet().difference(sw.keys.toSet()), isEmpty,
        reason: 'keys with English copy but no Kiswahili translation');
    expect(sw.keys.toSet().difference(en.keys.toSet()), isEmpty,
        reason: 'keys with Kiswahili copy but no English translation');
    expect(en, isNotEmpty);
  });

  test('no translation is blank', () {
    final blank = <String>[];
    for (final entry in {...en, ...sw}.entries) {
      for (final table in [en, sw]) {
        final value = table[entry.key];
        if (value == null || value.trim().isEmpty) blank.add(entry.key);
      }
    }
    expect(blank, isEmpty);
  });

  test('every static tr() key in lib/ resolves', () {
    final unmapped = _staticKeysUsedInLib()
        .where((key) => !en.containsKey(key) && !sw.containsKey(key))
        .toList()
      ..sort();
    expect(unmapped, isEmpty,
        reason: 'a rendered string would silently fall back to its raw key');
  });

  test('runtime-built clinic keys exist in both languages', () {
    const families = [
      'clinic.status.requested',
      'clinic.status.confirmed',
      'clinic.status.completed',
      'clinic.status.rescheduled',
      'clinic.status.cancelled',
      'clinic.status.noShow',
      'clinic.type.newPatient',
      'clinic.type.followUp',
      'clinic.type.routineReview',
      'clinic.type.labResults',
      'clinic.type.medicationReview',
      'clinic.type.vaccination',
      'clinic.type.other',
    ];
    for (final key in families) {
      expect(en[key], isNotNull, reason: key);
      expect(sw[key], isNotNull, reason: key);
    }
  });
}