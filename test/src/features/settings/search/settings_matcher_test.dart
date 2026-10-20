// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/search/settings_search_registry.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_en.dart';

SettingsSearchEntry _entry(String id, String title, {String? subtitle}) =>
    SettingsSearchEntry(
      id: id,
      title: (_) => title,
      subtitle: subtitle == null ? null : (_) => subtitle,
      breadcrumb: (_) => 'Page',
      open: (_) {},
      visible: (_, _) => true,
    );

void main() {
  final l = AppLocalizationsEn();

  List<String> idsOf(
    List<SettingsSearchEntry> entries,
    String query, {
    bool Function(String id) shown = _always,
  }) => matchSettingsEntries(
    entries: entries,
    l: l,
    query: query,
    isVisible: (e) => shown(e.id),
  ).map((e) => e.id).toList();

  group('matchSettingsEntries', () {
    test('matches title, subtitle, case, empty, cap and hidden entries', () {
      final entries = [
        _entry('a', 'App Theme Mode'),
        _entry('b', 'Clear Cache'),
        _entry('c', 'Show recommendations', subtitle: 'Similar titles row'),
      ];
      expect(idsOf(entries, 'theme'), ['a']);
      expect(idsOf(entries, 'similar'), ['c']);
      expect(idsOf(entries, 'THEME'), ['a']);
      expect(idsOf(entries, '  theme  '), ['a']);
      expect(idsOf(entries, ''), isEmpty);
      expect(idsOf(entries, '   '), isEmpty);

      final twelve = [for (var i = 0; i < 12; i++) _entry('e$i', 'Theme $i')];
      final capped = matchSettingsEntries(
        entries: twelve,
        l: l,
        query: 'theme',
        isVisible: (_) => true,
      );
      expect(capped, hasLength(10));
      expect(capped.map((e) => e.id), [for (var i = 0; i < 10; i++) 'e$i']);

      final hidden = [
        _entry('shown', 'Quick Search'),
        _entry('hidden', 'Quick Search Pro'),
      ];
      expect(idsOf(hidden, 'quick search', shown: (id) => id == 'shown'), [
        'shown',
      ]);
    });
  });
}

bool _always(String _) => true;
