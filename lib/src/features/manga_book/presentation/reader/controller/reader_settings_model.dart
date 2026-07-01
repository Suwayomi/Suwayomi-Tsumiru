// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../settings/presentation/reader/widgets/reader_invert_tap_tile/reader_invert_tap_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_magnifier_size_slider/reader_magnifier_size_slider.dart';
import '../../../../settings/presentation/reader/widgets/reader_orientation/reader_orientation.dart';
import '../../../../settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import '../../../../settings/presentation/reader/widgets/reader_pinch_to_zoom/reader_pinch_to_zoom.dart';
import '../../../../settings/presentation/reader/widgets/reader_tap_invert/reader_tap_invert.dart';
import '../../../../settings/presentation/reader/widgets/reader_zoom_toggles/reader_zoom_toggles.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/manga/manga_model.dart';
import '../../manga_details/controller/manga_details_controller.dart';
import 'reader_setting.dart';

part 'reader_settings_model.freezed.dart';
part 'reader_settings_model.g.dart';

/// Descriptor table mirroring exactly how each option persists today.
abstract final class ReaderSettings {
  /// Meta ?? sentinel: the app-wide default mode is dereferenced later by the
  /// engine — folding it in here would make "Default" unrepresentable.
  static const mode = ReaderSetting<ReaderMode>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerMode,
    fallback: ReaderMode.defaultReader,
  );

  static const navigationLayout = ReaderSetting<ReaderNavigationLayout>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerNavigationLayout,
    fallback: ReaderNavigationLayout.defaultNavigation,
  );

  static final sidePadding = ReaderSetting<double>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerPadding,
    global: readerPaddingKeyProvider,
    fallback: DBKeys.readerPadding.initial as double,
  );

  static final magnifierSize = ReaderSetting<double>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerMagnifierSize,
    global: readerMagnifierSizeKeyProvider,
    fallback: DBKeys.readerMagnifierSize.initial as double,
  );

  /// Global-only today: the reader never reads the per-series invert meta.
  static final invertTap = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: invertTapProvider,
    fallback: DBKeys.invertTap.initial as bool,
  );

  static final readerOrientation = ReaderSetting<ReaderOrientation>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerOrientation,
    global: readerOrientationKeyProvider,
    fallback: ReaderOrientation.defaultRotation,
  );

  /// 4-value successor of invertTap. Global side is the compat provider:
  /// new key ?? legacy bool (true→both). Writes only ever hit the new key.
  static final tapInvert = ReaderSetting<TapInvert>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerTapInvert,
    global: readerTapInvertCompatProvider,
    fallback: TapInvert.none,
  );

  // Zoom toggles are global reader prefs (Komikku parity — no per-series meta).
  static final pinchToZoom = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: pinchToZoomProvider,
    fallback: DBKeys.pinchToZoom.initial as bool,
  );

  static final doubleTapToZoom = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: doubleTapToZoomProvider,
    fallback: DBKeys.doubleTapToZoom.initial as bool,
  );

  static final disableZoomOut = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: disableZoomOutProvider,
    fallback: DBKeys.disableZoomOut.initial as bool,
  );

  static final disableZoomIn = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: disableZoomInProvider,
    fallback: DBKeys.disableZoomIn.initial as bool,
  );
}

@freezed
class ReaderSettingsState with _$ReaderSettingsState {
  const factory ReaderSettingsState({
    required ReaderMode readerMode,
    required ReaderNavigationLayout navigationLayout,
    required double sidePadding,
    required double magnifierSize,
    required bool invertTap,
    required ReaderOrientation readerOrientation,
    required TapInvert tapInvert,
    required bool pinchToZoom,
    required bool doubleTapToZoom,
    required bool disableZoomOut,
    required bool disableZoomIn,
  }) = _ReaderSettingsState;
}

/// Effective reader settings for one manga, seeded `perSeries ?? global` from
/// the existing providers/meta — the state home for the settings sheet.
@riverpod
class ReaderSettingsModel extends _$ReaderSettingsModel {
  // Captured at build: setters write via these, since the model's own ref is
  // outdated (assert-crash) between a global write and the rebuild it triggers.
  late PinchToZoom _pinchToZoom;
  late DoubleTapToZoom _doubleTapToZoom;
  late DisableZoomOut _disableZoomOut;
  late DisableZoomIn _disableZoomIn;

  @override
  ReaderSettingsState build(int mangaId) {
    _pinchToZoom = ref.read(pinchToZoomProvider.notifier);
    _doubleTapToZoom = ref.read(doubleTapToZoomProvider.notifier);
    _disableZoomOut = ref.read(disableZoomOutProvider.notifier);
    _disableZoomIn = ref.read(disableZoomInProvider.notifier);
    final meta =
        ref.watch(mangaWithIdProvider(mangaId: mangaId)).valueOrNull?.metaData;
    return ReaderSettingsState(
      readerMode: ReaderSettings.mode.resolveWith(ref, meta?.readerMode),
      navigationLayout: ReaderSettings.navigationLayout
          .resolveWith(ref, meta?.readerNavigationLayout),
      sidePadding:
          ReaderSettings.sidePadding.resolveWith(ref, meta?.readerPadding),
      magnifierSize: ReaderSettings.magnifierSize
          .resolveWith(ref, meta?.readerMagnifierSize),
      invertTap: ReaderSettings.invertTap.resolveWith(ref, null),
      readerOrientation: ReaderSettings.readerOrientation
          .resolveWith(ref, meta?.readerOrientation),
      tapInvert:
          ReaderSettings.tapInvert.resolveWith(ref, meta?.readerTapInvert),
      pinchToZoom: ReaderSettings.pinchToZoom.resolveWith(ref, null),
      doubleTapToZoom: ReaderSettings.doubleTapToZoom.resolveWith(ref, null),
      disableZoomOut: ReaderSettings.disableZoomOut.resolveWith(ref, null),
      disableZoomIn: ReaderSettings.disableZoomIn.resolveWith(ref, null),
    );
  }

  // Zoom toggles are global: write the app-wide provider, never manga meta.
  void setPinchToZoom(bool value) => _pinchToZoom.update(value);

  void setDoubleTapToZoom(bool value) => _doubleTapToZoom.update(value);

  void setDisableZoomOut(bool value) => _disableZoomOut.update(value);

  void setDisableZoomIn(bool value) => _disableZoomIn.update(value);

  Future<void> setReaderMode(ReaderMode mode) =>
      _patchMeta(MangaMetaKeys.readerMode, mode.name);

  Future<void> setNavigationLayout(ReaderNavigationLayout layout) =>
      _patchMeta(MangaMetaKeys.readerNavigationLayout, layout.name);

  Future<void> setSidePadding(double value) =>
      _patchMeta(MangaMetaKeys.readerPadding, value);

  Future<void> setMagnifierSize(double value) =>
      _patchMeta(MangaMetaKeys.readerMagnifierSize, value);

  Future<void> setReaderOrientation(ReaderOrientation orientation) =>
      _patchMeta(MangaMetaKeys.readerOrientation, orientation.name);

  /// Writes the NEW 4-value key only; the legacy invertTap bool is never
  /// destructively rewritten (compat read stays valid for a downgrade).
  Future<void> setTapInvert(TapInvert value) =>
      _patchMeta(MangaMetaKeys.readerTapInvert, value.name);

  /// Per-series write, mirroring the old drawer: patchMangaMeta then
  /// invalidate mangaWithIdProvider so every watcher re-reads fresh meta.
  Future<void> _patchMeta(MangaMetaKeys key, dynamic value) async {
    // Hold this autoDispose family open across the round-trip so a sheet
    // dismissed mid-write can't tear down ref before the invalidate.
    final link = ref.keepAlive();
    try {
      await AsyncValue.guard(
        () => ref.read(mangaBookRepositoryProvider).patchMangaMeta(
              mangaId: mangaId,
              key: key.key,
              value: value,
            ),
      );
      ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    } finally {
      link.close();
    }
  }
}

/// Plan-named alias for the resolved-settings family.
final readerEffectiveSettingsProvider = readerSettingsModelProvider;
