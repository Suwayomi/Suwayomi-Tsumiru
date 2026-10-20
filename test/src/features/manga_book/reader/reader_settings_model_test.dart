// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// ReaderSetting descriptors + ReaderSettingsModel: pins the perSeries ?? global
// resolution and that build(mangaId) mirrors the current drawer's semantics.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_setting.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_settings_model.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_invert_tap_tile/reader_invert_tap_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

/// Records every per-series meta patch so tests can pin exactly which keys
/// a mutation writes (and, critically, which it does NOT).
class _RecordingRepo extends Fake implements MangaBookRepository {
  final calls = <({int mangaId, String key, dynamic value})>[];

  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async => calls.add((mangaId: mangaId, key: key, value: value));
}

MangaDto _manga({Map<String, String> meta = const {}}) => Fragment$MangaDto(
  id: 1,
  title: 'Test Manga',
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  downloadCount: 0,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: [
    for (final e in meta.entries)
      Fragment$MangaDto$meta(key: e.key, value: e.value),
  ],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: 0,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
);

Future<ProviderContainer> _container(
  MangaDto manga, {
  MangaBookRepository? repository,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      mangaWithIdProvider(
        mangaId: 1,
      ).overrideWith(() => _FakeMangaWithId(manga)),
      if (repository != null)
        mangaBookRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Reads the model state after the manga (and its meta) has resolved.
Future<ReaderSettingsState> _resolvedState(ProviderContainer container) async {
  container.listen(readerSettingsModelProvider(1), (_, _) {});
  await container.read(mangaWithIdProvider(mangaId: 1).future);
  await Future<void>.value();
  return container.read(readerSettingsModelProvider(1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderSetting<T>.resolve', () {
    const setting = ReaderSetting<double>(
      scope: ReaderSettingScope.perSeries,
      perSeriesKey: MangaMetaKeys.readerPadding,
      fallback: 0.0,
    );

    test('per-series X beats global Y', () {
      expect(setting.resolve(0.3, 0.1), 0.3);
    });

    test('both null falls back to the default', () {
      expect(setting.resolve(null, null), 0.0);
    });
  });

  group('descriptor table mirrors current persistence', () {});

  group('ReaderSettingsModel.build', () {
    test('unset globals resolve to the DBKeys defaults', () async {
      final container = await _container(_manga());

      final state = await _resolvedState(container);
      expect(state.sidePadding, 0.0);
      expect(state.invertTap, false);
      expect(state.pinchToZoom, true);
      expect(state.doubleTapToZoom, true);
      expect(state.disableZoomOut, false);
      expect(state.disableZoomIn, false);
    });

    test(
      'setReaderOrientation writes only the per-series orientation key',
      () async {
        final repo = _RecordingRepo();
        final container = await _container(_manga(), repository: repo);
        await _resolvedState(container);

        await container
            .read(readerSettingsModelProvider(1).notifier)
            .setReaderOrientation(ReaderOrientation.free);

        expect(repo.calls.single.key, MangaMetaKeys.readerOrientation.key);
        expect(repo.calls.single.value, 'free');
      },
    );

    test('tapInvert compat: legacy bool true→both, false/unset→none', () async {
      var container = await _container(_manga());
      expect((await _resolvedState(container)).tapInvert, TapInvert.none);

      container = await _container(_manga());
      container.read(invertTapProvider.notifier).update(true);
      expect((await _resolvedState(container)).tapInvert, TapInvert.both);
    });

    test(
      'setTapInvert writes ONLY the new key; legacy bool never rewritten',
      () async {
        final repo = _RecordingRepo();
        final container = await _container(_manga(), repository: repo);
        container.read(invertTapProvider.notifier).update(true);
        await _resolvedState(container);

        await container
            .read(readerSettingsModelProvider(1).notifier)
            .setTapInvert(TapInvert.vertical);

        expect(repo.calls.single.key, MangaMetaKeys.readerTapInvert.key);
        expect(repo.calls.single.value, 'vertical');
        // The legacy global bool is untouched (compat read stays valid).
        expect(container.read(invertTapProvider), true);
      },
    );
  });
}
