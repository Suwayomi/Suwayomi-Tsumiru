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
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_setting.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_settings_model.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_invert_tap_tile/reader_invert_tap_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_magnifier_size_slider/reader_magnifier_size_slider.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_pinch_to_zoom/reader_pinch_to_zoom.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_zoom_toggles/reader_zoom_toggles.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
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
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/1',
    );

Future<ProviderContainer> _container(MangaDto manga) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    mangaWithIdProvider(mangaId: 1)
        .overrideWith(() => _FakeMangaWithId(manga)),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Reads the model state after the manga (and its meta) has resolved.
Future<ReaderSettingsState> _resolvedState(ProviderContainer container) async {
  container.listen(readerSettingsModelProvider(1), (_, __) {});
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

    test('per-series null falls back to global Y', () {
      expect(setting.resolve(null, 0.1), 0.1);
    });

    test('both null falls back to the default', () {
      expect(setting.resolve(null, null), 0.0);
    });
  });

  group('descriptor table mirrors current persistence', () {
    test('scopes + per-series keys match how each option persists today', () {
      expect(ReaderSettings.mode.scope, ReaderSettingScope.perSeries);
      expect(ReaderSettings.mode.perSeriesKey, MangaMetaKeys.readerMode);

      expect(
          ReaderSettings.navigationLayout.scope, ReaderSettingScope.perSeries);
      expect(ReaderSettings.navigationLayout.perSeriesKey,
          MangaMetaKeys.readerNavigationLayout);

      expect(ReaderSettings.sidePadding.scope, ReaderSettingScope.perSeries);
      expect(
          ReaderSettings.sidePadding.perSeriesKey, MangaMetaKeys.readerPadding);

      expect(ReaderSettings.magnifierSize.scope, ReaderSettingScope.perSeries);
      expect(ReaderSettings.magnifierSize.perSeriesKey,
          MangaMetaKeys.readerMagnifierSize);

      // Global-only today: the reader never reads the per-series invert meta.
      expect(ReaderSettings.invertTap.scope, ReaderSettingScope.global);
      expect(ReaderSettings.invertTap.perSeriesKey, isNull);
    });

    test('zoom toggles are global-only (Komikku parity, no per-series meta)',
        () {
      for (final setting in [
        ReaderSettings.pinchToZoom,
        ReaderSettings.doubleTapToZoom,
        ReaderSettings.disableZoomOut,
        ReaderSettings.disableZoomIn,
      ]) {
        expect(setting.scope, ReaderSettingScope.global);
        expect(setting.perSeriesKey, isNull);
      }
      // Defaults: gestures on, nothing disabled.
      expect(ReaderSettings.pinchToZoom.fallback, true);
      expect(ReaderSettings.doubleTapToZoom.fallback, true);
      expect(ReaderSettings.disableZoomOut.fallback, false);
      expect(ReaderSettings.disableZoomIn.fallback, false);
    });

    test('mode/nav fall back to the sentinel, not the app-wide default', () {
      // The drawer shows "Default" when no override is set; the app-wide mode
      // is dereferenced later by the engine. Folding it in here would make the
      // "Default" selection unrepresentable.
      expect(ReaderSettings.mode.fallback, ReaderMode.defaultReader);
      expect(ReaderSettings.navigationLayout.fallback,
          ReaderNavigationLayout.defaultNavigation);
    });
  });

  group('ReaderSettingsModel.build', () {
    test('seeds every field from per-series meta when set', () async {
      final container = await _container(_manga(meta: {
        'flutter_readerMode': 'singleHorizontalRTL',
        'flutter_readerNavigationLayout': 'edge',
        'flutter_readerPadding': '0.2',
        'flutter_readerMagnifierSize': '2.5',
      }));

      final state = await _resolvedState(container);
      expect(state.readerMode, ReaderMode.singleHorizontalRTL);
      expect(state.navigationLayout, ReaderNavigationLayout.edge);
      expect(state.sidePadding, 0.2);
      expect(state.magnifierSize, 2.5);
    });

    test('seeds from globals/sentinels when no per-series meta', () async {
      final container = await _container(_manga());
      container.read(readerPaddingKeyProvider.notifier).update(0.25);
      container.read(readerMagnifierSizeKeyProvider.notifier).update(1.5);
      container.read(invertTapProvider.notifier).update(true);

      final state = await _resolvedState(container);
      expect(state.readerMode, ReaderMode.defaultReader);
      expect(state.navigationLayout, ReaderNavigationLayout.defaultNavigation);
      expect(state.sidePadding, 0.25);
      expect(state.magnifierSize, 1.5);
      expect(state.invertTap, true);
    });

    test('unset globals resolve to the DBKeys defaults', () async {
      final container = await _container(_manga());

      final state = await _resolvedState(container);
      expect(state.sidePadding, 0.0);
      expect(state.magnifierSize, 1.0);
      expect(state.invertTap, false);
      expect(state.pinchToZoom, true);
      expect(state.doubleTapToZoom, true);
      expect(state.disableZoomOut, false);
      expect(state.disableZoomIn, false);
    });

    test('zoom toggles resolve the live global providers', () async {
      final container = await _container(_manga());
      container.read(pinchToZoomProvider.notifier).update(false);
      container.read(doubleTapToZoomProvider.notifier).update(false);
      container.read(disableZoomOutProvider.notifier).update(true);
      container.read(disableZoomInProvider.notifier).update(true);

      final state = await _resolvedState(container);
      expect(state.pinchToZoom, false);
      expect(state.doubleTapToZoom, false);
      expect(state.disableZoomOut, true);
      expect(state.disableZoomIn, true);
    });

    test('zoom setters write the global providers, not manga meta', () async {
      final container = await _container(_manga());
      await _resolvedState(container);

      final model = container.read(readerSettingsModelProvider(1).notifier);
      model.setPinchToZoom(false);
      model.setDoubleTapToZoom(false);
      model.setDisableZoomOut(true);
      model.setDisableZoomIn(true);

      expect(container.read(pinchToZoomProvider), false);
      expect(container.read(doubleTapToZoomProvider), false);
      expect(container.read(disableZoomOutProvider), true);
      expect(container.read(disableZoomInProvider), true);

      await Future<void>.value();
      final state = container.read(readerSettingsModelProvider(1));
      expect(state.pinchToZoom, false);
      expect(state.doubleTapToZoom, false);
      expect(state.disableZoomOut, true);
      expect(state.disableZoomIn, true);
    });

    test('invertTap ignores stale per-series meta (global-only today)',
        () async {
      final container = await _container(_manga(meta: {
        'flutter_readerNavigationLayoutInvert': 'true',
      }));

      final state = await _resolvedState(container);
      expect(state.invertTap, false,
          reason: 'no code path reads the per-series invert meta today');
    });

    test('readerEffectiveSettingsProvider is the model family', () async {
      final container = await _container(_manga(meta: {
        'flutter_readerPadding': '0.4',
      }));

      final state = await _resolvedState(container);
      expect(container.read(readerEffectiveSettingsProvider(1)), state);
      expect(
          container.read(readerEffectiveSettingsProvider(1)).sidePadding, 0.4);
    });
  });
}
