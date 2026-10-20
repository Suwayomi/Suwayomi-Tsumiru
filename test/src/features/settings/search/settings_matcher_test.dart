// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
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

  group('page searches', () {
    test('return their rows with breadcrumbs and tab indexes', () {
      List<SettingsSearchEntry> hitsOf(String query) => matchSettingsEntries(
        entries: allSettingsSearchEntries,
        l: l,
        query: query,
        isVisible: (_) => true,
      );

      final zoom = hitsOf('zoom');
      expect(zoom.map((e) => e.id).toList(), [
        'disableZoomIn',
        'pagedDoubleTapToZoom',
        'pagedPinchToZoom',
        'pagedDisableZoomOut',
        'longStripDoubleTapToZoom',
        'longStripPinchToZoom',
        'longStripDisableZoomOut',
      ]);
      final paged = '${l.reader} › ${l.readerGroupPagerViewer}';
      final strip = '${l.reader} › ${l.readerGroupWebtoonViewer}';
      for (final hit in zoom.take(4)) {
        expect(hit.breadcrumb(l), paged, reason: hit.id);
      }
      for (final hit in zoom.skip(4)) {
        expect(hit.breadcrumb(l), strip, reason: hit.id);
      }

      final socks = hitsOf('socks');
      expect(socks.map((e) => e.id).toList(), [
        'enableSocksProxy',
        'socksVersion',
        'socksHost',
        'socksPort',
        'socksUserName',
        'socksPassword',
      ]);
      for (final hit in socks) {
        expect(
          hit.breadcrumb(l),
          '${l.server} › ${l.socksProxy}',
          reason: hit.id,
        );
      }

      final bookmarked = hitsOf('bookmarked');
      expect(bookmarked.map((e) => e.id).toList(), [
        'serverDeleteWithBookmark',
        'deviceDeleteWithBookmark',
      ]);
      expect(bookmarked.map((e) => e.breadcrumb(l)).toList(), [
        '${l.downloads} › ${l.downloadsServerTab}',
        '${l.downloads} › ${l.downloadsOnDeviceTab}',
      ]);
      expect(bookmarked.map((e) => e.tabIndex).toList(), [0, 1]);
    });
  });

  group('real entry visibility', () {
    testWidgets('follows runtime settings and loaded state', (tester) async {
      late WidgetRef refOf;
      late BuildContext ctxOf;

      Future<void> pumpScope(ProviderContainer container) async {
        // Unmount any previous tree first: updating an existing scope in
        // place reuses its container, so a reused notifier re-runs
        // initialize().
        await tester.pumpWidget(const SizedBox());
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

      Future<ProviderContainer> containerWith(List<Override> overrides) async {
        SharedPreferences.setMockInitialValues({});
        final sp = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sp),
            ...overrides,
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      SettingsSearchEntry entryById(String id) =>
          allSettingsSearchEntries.singleWhere((e) => e.id == id);

      // Quick Search mirrors the keyboard runtime.
      await pumpScope(await containerWith([]));
      expect(entryById('quickSearch').visible(refOf, ctxOf), isKeyboardRuntime);

      // Retry delay follows auto-refresh.
      await pumpScope(
        await containerWith([
          autoRefreshOnTimeoutProvider.overrideWith(_AutoRefreshOff.new),
        ]),
      );
      expect(entryById('autoRefreshRetryDelay').visible(refOf, ctxOf), isFalse);
      expect(entryById('autoRefreshOnTimeout').visible(refOf, ctxOf), isTrue);
      await pumpScope(
        await containerWith([
          autoRefreshOnTimeoutProvider.overrideWith(_AutoRefreshOn.new),
        ]),
      );
      expect(entryById('autoRefreshRetryDelay').visible(refOf, ctxOf), isTrue);

      // SOCKS host follows SOCKS, both ways.
      for (final on in [false, true]) {
        final container = await containerWith([
          settingsProvider.overrideWith(() => _SocksSettings(on)),
        ]);
        await container.read(settingsProvider.future);
        await pumpScope(container);
        expect(entryById('socksHost').visible(refOf, ctxOf), on);
        expect(entryById('enableSocksProxy').visible(refOf, ctxOf), isTrue);
        await tester.pumpAndSettle();
      }

      // Sync now waits for a host and key; its data row does not.
      Future<bool> syncNowVisible(SyncYomiSettings settings) async {
        final container = await containerWith([
          syncYomiSettingsProvider.overrideWith((ref) async => settings),
        ]);
        await container.read(syncYomiSettingsProvider.future);
        await pumpScope(container);
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

      // Server-gated rows stay hidden while settings are not loaded.
      await pumpScope(await containerWith([...unreachableServerStubs]));
      expect(entryById('showNsfw').visible(refOf, ctxOf), isTrue);
      for (final id in [
        'parallelSourceRequests',
        'localSourceLocation',
        'extensionStores',
      ]) {
        expect(entryById(id).visible(refOf, ctxOf), isFalse, reason: id);
      }
      for (final entry in librarySettingsSearchEntries) {
        expect(entry.visible(refOf, ctxOf), isFalse, reason: entry.id);
      }
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

      // And appear once settings load.
      final loaded = await containerWith([
        settingsProvider.overrideWith(() => _SocksSettings(true)),
      ]);
      await loaded.read(settingsProvider.future);
      await pumpScope(loaded);
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

      final plain = settingsTitleSpans(
        title: 'Clear Cache',
        query: 'image',
        match: match,
      );
      expect(plain, hasLength(1));
      expect(plain.single.text, 'Clear Cache');
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
