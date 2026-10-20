// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Regression guard: a bulk mark-read action (MultiChaptersActionIcon) fires
// maybeDeleteOnManualLocal/maybeDeleteOnManualServer/maybeTrackProgressOnReadFetch
// via `unawaited(...)` AFTER an earlier `await`. If the widget that pressed the
// button has since unmounted (the selection action bar closes on a successful
// mark-read), a `WidgetRef` captured from that widget throws "Bad state: Using
// ref... is unsafe" the instant these functions try to read a provider — even
// on their very first line, before any await of their own. These functions now
// take a plain read function (`OfflineRead`/`TrackRead`) instead of a
// `WidgetRef`, so callers can pass a `ProviderContainer.read` obtained up front
// — a container tied to a persistent ancestor `ProviderScope` outlives any one
// descendant widget being removed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/chapter_download_engine.dart';
import 'package:tsumiru/src/features/offline/data/offline_background_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_manager.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/fake_page_store.dart';
import '../../../../helpers/offline_test_db.dart';

class _FixedServerDeleteSettings extends DeleteChaptersSettingsController {
  _FixedServerDeleteSettings(this.settings);
  final DeleteChaptersSettings settings;

  @override
  Future<DeleteChaptersSettings> build() async => settings;
}

void main() {
  late OfflineDatabase db;
  final store = FakePageStore();

  setUp(() {
    OfflineDownloadCoordinator.resetSharedStateForTest();
    db = testOfflineDatabase();
  });
  tearDown(() => db.close());

  OfflineDownloadCoordinator buildCoordinator() => OfflineDownloadCoordinator(
    db: db,
    engine: ChapterDownloadEngine(
      fetchPage: (_) async => throw UnimplementedError(),
      writePage: store,
      refreshAuth: () async => false,
    ),
    store: store,
    resolvePages: (_) async => const [],
  );

  OfflineDownloadManager buildManager() => OfflineDownloadManager(
    db: db,
    store: store,
    fetchPageUrls: (_) async => const [],
    fetchBytes: (_) async => throw UnimplementedError(),
  );

  /// Pumps a persistent [ProviderScope] with a REMOVABLE inner [Consumer] —
  /// mirroring the real shape (an app-root scope hosting a selection action
  /// bar that closes on its own). Returns the inner widget's [WidgetRef], a
  /// [ProviderContainer] obtained independently of it, and a function that
  /// removes the inner widget (simulating the action bar closing / the icon
  /// unmounting) while the outer scope — and so the container — survives.
  Future<
    ({
      WidgetRef ref,
      ProviderContainer container,
      Future<void> Function() unmountChild,
    })
  >
  harness(WidgetTester tester, {bool deleteManuallyMarkedRead = true}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final showChild = ValueNotifier<bool>(true);
    late WidgetRef captured;
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineActiveProvider.overrideWithValue(true),
          offlineDatabaseProvider.overrideWithValue(db),
          offlinePathsProvider.overrideWithValue(const OfflinePaths('/tmp/x')),
          offlinePageStoreProvider.overrideWithValue(store),
          offlineDownloadCoordinatorProvider.overrideWithValue(
            buildCoordinator(),
          ),
          offlineDownloadManagerProvider.overrideWithValue(buildManager()),
          localDeleteSettingsProvider.overrideWithValue(
            DeleteChaptersSettings(
              deleteWhileReading: 0,
              deleteManuallyMarkedRead: deleteManuallyMarkedRead,
              deleteWithBookmark: false,
            ),
          ),
          // maybeDeleteOnManualServer gates on the SERVER copy of this setting
          // (fetched over GraphQL in real use) — fixed here so the no-op path
          // is deterministic instead of relying on the test having no server.
          deleteChaptersSettingsControllerProvider.overrideWith(
            () => _FixedServerDeleteSettings(
              DeleteChaptersSettings(
                deleteWhileReading: 0,
                deleteManuallyMarkedRead: deleteManuallyMarkedRead,
                deleteWithBookmark: false,
              ),
            ),
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return ValueListenableBuilder<bool>(
              valueListenable: showChild,
              builder: (context, show, _) => show
                  ? Consumer(
                      builder: (context, ref, _) {
                        captured = ref;
                        return const SizedBox();
                      },
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );

    Future<void> unmountChild() async {
      showChild.value = false;
      await tester.pump();
    }

    return (ref: captured, container: container, unmountChild: unmountChild);
  }

  testWidgets(
    'a WidgetRef captured before the widget unmounts throws on the very next read '
    '(reproduces the reported crash)',
    (tester) async {
      final h = await harness(tester);
      await h.unmountChild();

      expect(
        () => h.ref.read(offlineActiveProvider),
        throwsA(isA<StateError>()),
        reason:
            'this is exactly the crash from the field log: '
            'ConsumerStatefulElement.read throwing once its element is disposed',
      );
    },
  );

  testWidgets(
    'maybeDeleteOnManualLocal deletes the device copy via a container obtained '
    'from a since-unmounted widget, where the widget\'s own ref would throw',
    (tester) async {
      await db.upsertChapterMetadata(
        id: 10,
        mangaId: 1,
        name: 'c',
        chapterIndex: 1,
        isRead: true,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 1,
        updatedAt: DateTime(2026),
      );
      await db.setChapterDeviceState(
        10,
        OfflineDeviceState.downloaded,
        bytes: 5,
      );

      final h = await harness(tester);
      await h.unmountChild();

      // The widget that would have called this is gone — only the container
      // (obtained up front, independent of that widget) is used here, exactly
      // as multi_chapters_action_icon.dart now does.
      await maybeDeleteOnManualLocal(h.container.read, chapterId: 10);

      final c = await h.container
          .read(offlineRepositoryProvider)
          .chapterById(10);
      expect(
        c?.deviceState,
        OfflineDeviceState.none,
        reason:
            'the delete-on-manual-read side effect must still run even '
            'though the originating widget already unmounted',
      );
    },
  );
}
