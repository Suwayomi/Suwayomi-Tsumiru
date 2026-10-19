// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/presentation/general/timeout_settings/timeout_settings_section.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/settings/search/settings_search_registry.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations_en.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';

import '../../../../helpers/unreachable_server_stubs.dart';

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
      final entries = [
        _entry('a', 'App Theme Mode'),
        _entry('b', 'Clear Cache'),
      ];
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
      expect(idsOf(entries, 'quick search', shown: (id) => id == 'shown'), [
        'shown',
      ]);
    });
  });

  group('real entry visibility', () {
    late WidgetRef refOf;
    late BuildContext ctxOf;

    Future<void> pumpScope(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
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

    testWidgets('socks host hidden while SOCKS is off', (tester) async {
      Future<void> pumpSocks(WidgetTester tester, bool on) async {
        SharedPreferences.setMockInitialValues({});
        final sp = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sp),
            settingsProvider.overrideWith(() => _SocksSettings(on)),
          ],
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);
        await pumpScope(tester, container);
      }

      await pumpSocks(tester, false);
      expect(entryById('socksHost').visible(refOf, ctxOf), isFalse);
      expect(entryById('enableSocksProxy').visible(refOf, ctxOf), isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('socks host shown while SOCKS is on', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          settingsProvider.overrideWith(() => _SocksSettings(true)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      await pumpScope(tester, container);
      expect(entryById('socksHost').visible(refOf, ctxOf), isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('sync now hidden until host and key are set', (tester) async {
      Future<bool> syncNowVisible(SyncYomiSettings settings) async {
        SharedPreferences.setMockInitialValues({});
        final sp = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sp),
            syncYomiSettingsProvider.overrideWith((ref) async => settings),
          ],
        );
        addTearDown(container.dispose);
        await container.read(syncYomiSettingsProvider.future);
        await pumpScope(tester, container);
        return entryById('syncYomiSyncNow').visible(refOf, ctxOf);
      }

      const unconfigured = SyncYomiSettings(
        enabled: true,
        host: '',
        apiKey: '',
        interval: 'PT0S',
        dataManga: false,
        dataChapters: false,
        dataCategories: false,
        dataHistory: false,
        dataTracking: false,
      );
      const configured = SyncYomiSettings(
        enabled: true,
        host: 'https://sync.example',
        apiKey: 'key',
        interval: 'PT1H',
        dataManga: true,
        dataChapters: false,
        dataCategories: false,
        dataHistory: false,
        dataTracking: false,
      );
      expect(await syncNowVisible(unconfigured), isFalse);
      expect(await syncNowVisible(configured), isTrue);
      expect(entryById('syncYomiSyncData').visible(refOf, ctxOf), isTrue);
    });

    testWidgets('browse server rows hidden while settings are not loaded', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          ...unreachableServerStubs,
        ],
      );
      addTearDown(container.dispose);
      await pumpScope(tester, container);
      expect(entryById('showNsfw').visible(refOf, ctxOf), isTrue);
      for (final id in [
        'parallelSourceRequests',
        'localSourceLocation',
        'extensionStores',
      ]) {
        expect(entryById(id).visible(refOf, ctxOf), isFalse, reason: id);
      }
      await tester.pumpAndSettle();
    });

    testWidgets('library entries hidden while settings are not loaded', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          ...unreachableServerStubs,
        ],
      );
      addTearDown(container.dispose);
      await pumpScope(tester, container);
      for (final entry in librarySettingsSearchEntries) {
        expect(entry.visible(refOf, ctxOf), isFalse, reason: entry.id);
      }
      await tester.pumpAndSettle();
    });

    testWidgets(
      'server downloads and automatic backup rows hidden while settings are not loaded',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final sp = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sp),
            ...unreachableServerStubs,
          ],
        );
        addTearDown(container.dispose);
        await pumpScope(tester, container);
        for (final id in [
          'downloadLocation',
          'saveAsCbz',
          'serverDeleteManuallyMarkedRead',
          'serverDeleteWhileReading',
          'serverDeleteWithBookmark',
          'autoDownloadNewChapters',
          'chapterDownloadLimit',
          'excludeEntryWithUnreadChapters',
          'autoDownloadCategories',
          'backupLocation',
          'backupTime',
          'backupInterval',
          'backupCleanup',
        ]) {
          expect(entryById(id).visible(refOf, ctxOf), isFalse, reason: id);
        }
        expect(entryById('createBackup').visible(refOf, ctxOf), isTrue);
        expect(entryById('restoreBackup').visible(refOf, ctxOf), isTrue);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('server-gated rows shown once settings load', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          settingsProvider.overrideWith(() => _SocksSettings(true)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      await pumpScope(tester, container);
      for (final id in [
        'parallelSourceRequests',
        'categories',
        'downloadLocation',
        'backupLocation',
      ]) {
        expect(entryById(id).visible(refOf, ctxOf), isTrue, reason: id);
      }
      await tester.pumpAndSettle();
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

SettingsDto _socksSettings(bool on) => Fragment$SettingsDto(
  backupInterval: 0,
  backupPath: '',
  backupTTL: 0,
  backupTime: '',
  ip: '',
  port: 0,
  socksProxyEnabled: on,
  socksProxyHost: '',
  socksProxyPassword: '',
  socksProxyPort: '',
  socksProxyUsername: '',
  socksProxyVersion: 5,
  flareSolverrEnabled: false,
  flareSolverrSessionName: '',
  flareSolverrSessionTtl: 0,
  flareSolverrTimeout: 0,
  flareSolverrUrl: '',
  debugLogsEnabled: false,
  systemTrayEnabled: false,
  extensionRepos: const [],
  maxSourcesInParallel: 0,
  localSourcePath: '',
  globalUpdateInterval: 12,
  updateMangas: false,
  excludeCompleted: false,
  excludeNotStarted: false,
  excludeUnreadChapters: false,
  downloadAsCbz: false,
  downloadsPath: '',
  autoDownloadNewChapters: false,
  autoDownloadNewChaptersLimit: 0,
  excludeEntryWithUnreadChapters: false,
);

class _SocksSettings extends Settings {
  _SocksSettings(this.on);

  final bool on;

  @override
  Future<SettingsDto?> build() async => _socksSettings(on);
}
