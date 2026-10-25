// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Mount test: opening a cover preview must not throw during initHook.
// precacheImage resolves inherited widgets, which is forbidden inside a
// useEffect callback (debug assert); the probe has to run after the first
// frame instead.

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/browse_center/presentation/global_search/controller/source_quick_search_controller.dart';
import 'package:tsumiru/src/features/manga_book/data/cover_search/cover_site_search.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/edit_cover_picker.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';

class _InMemorySecureStorage implements FlutterSecureStorage {
  final _store = <String, String>{};
  @override
  Future<void> write({
    required String key,
    required String? value,
    iOptions,
    aOptions,
    lOptions,
    webOptions,
    mOptions,
    wOptions,
  }) async {
    value == null ? _store.remove(key) : _store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    iOptions,
    aOptions,
    lOptions,
    webOptions,
    mOptions,
    wOptions,
  }) async => _store[key];

  @override
  Future<void> delete({
    required String key,
    iOptions,
    aOptions,
    lOptions,
    webOptions,
    mOptions,
    wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not stubbed');
}

/// Every cover load fails, so the preview must keep Save disabled.
class _FailingCache extends Fake implements CacheManager, ImageCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => Stream.error(StateError('cover probe failed'));

  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) => Stream.error(StateError('cover probe failed'));
}

MangaDto _manga() => Fragment$MangaDto(
  id: 1,
  title: 'M',
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: 0,
  ),
);

class _PickerHost extends ConsumerWidget {
  const _PickerHost(this.manga);
  final MangaDto manga;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showEditCoverPicker(context, ref, manga),
          child: const Text('open picker'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('opening a cover preview keeps Save disabled on load failure', (
    tester,
  ) async {
    // The dialog needs room; the default 800x600 surface overflows it.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const candidates = <CoverCandidate>[
      (title: 'Candidate One', coverUrl: 'https://example.com/cover.jpg'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureStorageProvider.overrideWithValue(_InMemorySecureStorage()),
          coverCacheManagerProvider.overrideWithValue(_FailingCache()),
          quickSearchResultsProvider(
            query: 'M',
          ).overrideWithValue(const AsyncData<List<QuickSearchResults>>([])),
          for (final site in CoverSite.values)
            coverSiteResultsProvider(site, query: 'M').overrideWith(
              (ref) => Future.value(
                site == CoverSite.anilist
                    ? candidates
                    : const <CoverCandidate>[],
              ),
            ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _PickerHost(_manga()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Candidate One'));
    await tester.pump();

    // The preview opens without throwing, and Save stays disabled while the
    // probe is still running.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );

    // The probe fails, so Save stays disabled for the broken image.
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
  });
}
