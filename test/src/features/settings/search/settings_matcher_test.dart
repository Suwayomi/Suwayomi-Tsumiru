// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/settings/presentation/general/timeout_settings/timeout_settings_section.dart';
import 'package:tsumiru/src/features/settings/search/settings_search_registry.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_en.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';

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
    test('matches on title', () {
      final entries = [_entry('a', 'App Theme Mode'), _entry('b', 'Clear Cache')];
      expect(idsOf(entries, 'theme'), ['a']);
    });

    test('matches on subtitle', () {
      final entries = [
        _entry('a', 'Show recommendations', subtitle: 'Similar titles row'),
        _entry('b', 'Clear Cache'),
      ];
      expect(idsOf(entries, 'similar'), ['a']);
    });

    test('is case-insensitive', () {
      final entries = [_entry('a', 'App Theme Mode')];
      expect(idsOf(entries, 'THEME'), ['a']);
      expect(idsOf(entries, '  theme  '), ['a']);
    });

    test('empty query matches nothing', () {
      final entries = [_entry('a', 'App Theme Mode')];
      expect(idsOf(entries, ''), isEmpty);
      expect(idsOf(entries, '   '), isEmpty);
    });

    test('caps at 10 in registry order', () {
      final entries = [for (var i = 0; i < 12; i++) _entry('e$i', 'Theme $i')];
      final out = matchSettingsEntries(
        entries: entries,
        l: l,
        query: 'theme',
        isVisible: (_) => true,
      );
      expect(out, hasLength(10));
      expect(out.map((e) => e.id), [for (var i = 0; i < 10; i++) 'e$i']);
    });

    test('excludes hidden entries', () {
      final entries = [
        _entry('shown', 'Quick Search'),
        _entry('hidden', 'Quick Search Pro'),
      ];
      expect(
        idsOf(entries, 'quick search', shown: (id) => id == 'shown'),
        ['shown'],
      );
    });
  });

  group('real entry visibility', () {
    late WidgetRef refOf;
    late BuildContext ctxOf;

    Future<void> pumpScope(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              refOf = ref;
              ctxOf = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
    }

    Future<ProviderContainer> containerWithMocks() async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      return container;
    }

    SettingsSearchEntry entryById(String id) =>
        allSettingsSearchEntries.singleWhere((e) => e.id == id);

    testWidgets('Quick Search mirrors the keyboard runtime', (tester) async {
      final container = await containerWithMocks();
      await pumpScope(tester, container);
      expect(entryById('quickSearch').visible(refOf, ctxOf), isKeyboardRuntime);
    });

    testWidgets('retry delay hidden while auto-refresh is off', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          autoRefreshOnTimeoutProvider.overrideWith(_AutoRefreshOff.new),
        ],
      );
      addTearDown(container.dispose);
      await pumpScope(tester, container);
      expect(entryById('autoRefreshRetryDelay').visible(refOf, ctxOf), isFalse);
      expect(entryById('autoRefreshOnTimeout').visible(refOf, ctxOf), isTrue);
    });

    testWidgets('retry delay shown while auto-refresh is on', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          autoRefreshOnTimeoutProvider.overrideWith(_AutoRefreshOn.new),
        ],
      );
      addTearDown(container.dispose);
      await pumpScope(tester, container);
      expect(entryById('autoRefreshRetryDelay').visible(refOf, ctxOf), isTrue);
    });
  });

  group('settingsTitleSpans', () {
    const match = TextStyle(fontWeight: FontWeight.w600);

    test('splits around the first match', () {
      final spans = settingsTitleSpans(
        title: 'App Theme Mode',
        query: 'theme',
        match: match,
      );
      expect(spans, hasLength(3));
      expect(spans[0].text, 'App ');
      expect(spans[1].text, 'Theme');
      expect(spans[1].style, match);
      expect(spans[2].text, ' Mode');
    });

    test('plain span when the match is subtitle-only', () {
      final spans = settingsTitleSpans(
        title: 'Clear Cache',
        query: 'image',
        match: match,
      );
      expect(spans, hasLength(1));
      expect(spans.single.text, 'Clear Cache');
    });
  });
}

bool _always(String _) => true;

class _AutoRefreshOn extends AutoRefreshOnTimeout {
  @override
  bool? build() => true;
}

class _AutoRefreshOff extends AutoRefreshOnTimeout {
  @override
  bool? build() => false;
}
