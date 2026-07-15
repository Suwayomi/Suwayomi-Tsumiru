import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/go_to_targets.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('en'));

  test('matches a settings destination by label substring', () {
    final hits = matchGoToTargets('read', l, includeHotkeys: true);
    expect(hits.any((t) => t.label(l) == l.reader), isTrue);
  });

  test('empty query returns nothing', () {
    expect(matchGoToTargets('', l, includeHotkeys: true), isEmpty);
  });

  test('hotkeys destination excluded when includeHotkeys is false', () {
    final withHk = matchGoToTargets('key', l, includeHotkeys: true);
    final without = matchGoToTargets('key', l, includeHotkeys: false);
    expect(withHk.length, greaterThan(without.length));
  });

  test('extra targets (categories) are matched and appended', () {
    final cat = GoToTarget(
        label: (_) => 'Seinen', icon: Icons.folder, navigate: (_) {});
    final hits = matchGoToTargets('sein', l, includeHotkeys: true, extra: [cat]);
    expect(hits, contains(cat));
  });
}
