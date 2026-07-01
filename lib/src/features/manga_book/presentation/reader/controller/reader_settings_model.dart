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
import '../../../../settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_navigation_layout_tile/reader_navigation_layout_tile.dart';
import '../../../../settings/presentation/reader/widgets/reader_orientation/reader_orientation.dart';
import '../../../../settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import '../../../../settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../../../../settings/presentation/reader/widgets/reader_pinch_to_zoom/reader_pinch_to_zoom.dart';
import '../../../../settings/presentation/reader/widgets/reader_tap_invert/reader_tap_invert.dart';
import '../../../../settings/presentation/reader/widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
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

  // Paged parity prefs (Komikku ReaderPreferences — all global).
  static final imageScaleType = ReaderSetting<ImageScaleType>(
    scope: ReaderSettingScope.global,
    global: imageScaleTypeKeyProvider,
    fallback: DBKeys.imageScaleType.initial as ImageScaleType,
  );

  static final zoomStart = ReaderSetting<ZoomStart>(
    scope: ReaderSettingScope.global,
    global: zoomStartKeyProvider,
    fallback: DBKeys.zoomStart.initial as ZoomStart,
  );

  static final pageLayout = ReaderSetting<PageLayout>(
    scope: ReaderSettingScope.global,
    global: pageLayoutKeyProvider,
    fallback: DBKeys.pageLayout.initial as PageLayout,
  );

  static final centerMarginType = ReaderSetting<CenterMarginType>(
    scope: ReaderSettingScope.global,
    global: centerMarginTypeKeyProvider,
    fallback: DBKeys.centerMarginType.initial as CenterMarginType,
  );

  static final landscapeZoom = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: landscapeZoomProvider,
    fallback: DBKeys.landscapeZoom.initial as bool,
  );

  static final navigateToPan = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: navigateToPanProvider,
    fallback: DBKeys.navigateToPan.initial as bool,
  );

  static final invertDoublePages = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: invertDoublePagesProvider,
    fallback: DBKeys.invertDoublePages.initial as bool,
  );

  static final cropBorders = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: cropBordersProvider,
    fallback: DBKeys.cropBorders.initial as bool,
  );

  static final smallerTapZones = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: smallerTapZonesProvider,
    fallback: DBKeys.smallerTapZones.initial as bool,
  );

  static final animatePageTransitions = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: animatePageTransitionsProvider,
    fallback: DBKeys.animatePageTransitions.initial as bool,
  );

  // Long-strip parity prefs (all global).
  static final webtoonScaleType = ReaderSetting<WebtoonScaleType>(
    scope: ReaderSettingScope.global,
    global: webtoonScaleTypeKeyProvider,
    fallback: DBKeys.webtoonScaleType.initial as WebtoonScaleType,
  );

  static final cropBordersWebtoon = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: cropBordersWebtoonProvider,
    fallback: DBKeys.cropBordersWebtoon.initial as bool,
  );

  static final cropBordersGaps = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: cropBordersGapsProvider,
    fallback: DBKeys.cropBordersGaps.initial as bool,
  );

  static final smoothAutoScroll = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: smoothAutoScrollProvider,
    fallback: DBKeys.smoothAutoScroll.initial as bool,
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
    required ImageScaleType imageScaleType,
    required ZoomStart zoomStart,
    required PageLayout pageLayout,
    required CenterMarginType centerMarginType,
    required bool landscapeZoom,
    required bool navigateToPan,
    required bool invertDoublePages,
    required bool cropBorders,
    required bool smallerTapZones,
    required bool animatePageTransitions,
    required WebtoonScaleType webtoonScaleType,
    required bool cropBordersWebtoon,
    required bool cropBordersGaps,
    required bool smoothAutoScroll,
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
  late ImageScaleTypeKey _imageScaleType;
  late ZoomStartKey _zoomStart;
  late PageLayoutKey _pageLayout;
  late CenterMarginTypeKey _centerMarginType;
  late LandscapeZoom _landscapeZoom;
  late NavigateToPan _navigateToPan;
  late InvertDoublePages _invertDoublePages;
  late CropBorders _cropBorders;
  late SmallerTapZones _smallerTapZones;
  late AnimatePageTransitions _animatePageTransitions;
  late WebtoonScaleTypeKey _webtoonScaleType;
  late CropBordersWebtoon _cropBordersWebtoon;
  late CropBordersGaps _cropBordersGaps;
  late SmoothAutoScroll _smoothAutoScroll;
  // Globals of the per-series fields, for the "For this series" OFF path.
  late ReaderModeKey _readerModeKey;
  late ReaderNavigationLayoutKey _navigationLayoutKey;
  late ReaderOrientationKey _readerOrientationKey;
  late ReaderTapInvertKey _readerTapInvertKey;
  late ReaderPaddingKey _readerPaddingKey;
  late ReaderMagnifierSizeKey _readerMagnifierSizeKey;

  @override
  ReaderSettingsState build(int mangaId) {
    _pinchToZoom = ref.read(pinchToZoomProvider.notifier);
    _doubleTapToZoom = ref.read(doubleTapToZoomProvider.notifier);
    _disableZoomOut = ref.read(disableZoomOutProvider.notifier);
    _disableZoomIn = ref.read(disableZoomInProvider.notifier);
    _imageScaleType = ref.read(imageScaleTypeKeyProvider.notifier);
    _zoomStart = ref.read(zoomStartKeyProvider.notifier);
    _pageLayout = ref.read(pageLayoutKeyProvider.notifier);
    _centerMarginType = ref.read(centerMarginTypeKeyProvider.notifier);
    _landscapeZoom = ref.read(landscapeZoomProvider.notifier);
    _navigateToPan = ref.read(navigateToPanProvider.notifier);
    _invertDoublePages = ref.read(invertDoublePagesProvider.notifier);
    _cropBorders = ref.read(cropBordersProvider.notifier);
    _smallerTapZones = ref.read(smallerTapZonesProvider.notifier);
    _animatePageTransitions = ref.read(animatePageTransitionsProvider.notifier);
    _webtoonScaleType = ref.read(webtoonScaleTypeKeyProvider.notifier);
    _cropBordersWebtoon = ref.read(cropBordersWebtoonProvider.notifier);
    _cropBordersGaps = ref.read(cropBordersGapsProvider.notifier);
    _smoothAutoScroll = ref.read(smoothAutoScrollProvider.notifier);
    _readerModeKey = ref.read(readerModeKeyProvider.notifier);
    _navigationLayoutKey = ref.read(readerNavigationLayoutKeyProvider.notifier);
    _readerOrientationKey = ref.read(readerOrientationKeyProvider.notifier);
    _readerTapInvertKey = ref.read(readerTapInvertKeyProvider.notifier);
    _readerPaddingKey = ref.read(readerPaddingKeyProvider.notifier);
    _readerMagnifierSizeKey = ref.read(readerMagnifierSizeKeyProvider.notifier);
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
      imageScaleType: ReaderSettings.imageScaleType.resolveWith(ref, null),
      zoomStart: ReaderSettings.zoomStart.resolveWith(ref, null),
      pageLayout: ReaderSettings.pageLayout.resolveWith(ref, null),
      centerMarginType: ReaderSettings.centerMarginType.resolveWith(ref, null),
      landscapeZoom: ReaderSettings.landscapeZoom.resolveWith(ref, null),
      navigateToPan: ReaderSettings.navigateToPan.resolveWith(ref, null),
      invertDoublePages:
          ReaderSettings.invertDoublePages.resolveWith(ref, null),
      cropBorders: ReaderSettings.cropBorders.resolveWith(ref, null),
      smallerTapZones: ReaderSettings.smallerTapZones.resolveWith(ref, null),
      animatePageTransitions:
          ReaderSettings.animatePageTransitions.resolveWith(ref, null),
      webtoonScaleType: ReaderSettings.webtoonScaleType.resolveWith(ref, null),
      cropBordersWebtoon:
          ReaderSettings.cropBordersWebtoon.resolveWith(ref, null),
      cropBordersGaps: ReaderSettings.cropBordersGaps.resolveWith(ref, null),
      smoothAutoScroll: ReaderSettings.smoothAutoScroll.resolveWith(ref, null),
    );
  }

  // Zoom toggles are global: write the app-wide provider, never manga meta.
  void setPinchToZoom(bool value) => _pinchToZoom.update(value);

  void setDoubleTapToZoom(bool value) => _doubleTapToZoom.update(value);

  void setDisableZoomOut(bool value) => _disableZoomOut.update(value);

  void setDisableZoomIn(bool value) => _disableZoomIn.update(value);

  // Parity prefs are global too (Komikku keeps them in ReaderPreferences).
  void setImageScaleType(ImageScaleType value) => _imageScaleType.update(value);

  void setZoomStart(ZoomStart value) => _zoomStart.update(value);

  void setPageLayout(PageLayout value) => _pageLayout.update(value);

  void setCenterMarginType(CenterMarginType value) =>
      _centerMarginType.update(value);

  void setLandscapeZoom(bool value) => _landscapeZoom.update(value);

  void setNavigateToPan(bool value) => _navigateToPan.update(value);

  void setInvertDoublePages(bool value) => _invertDoublePages.update(value);

  void setCropBorders(bool value) => _cropBorders.update(value);

  void setSmallerTapZones(bool value) => _smallerTapZones.update(value);

  void setAnimatePageTransitions(bool value) =>
      _animatePageTransitions.update(value);

  void setWebtoonScaleType(WebtoonScaleType value) =>
      _webtoonScaleType.update(value);

  void setCropBordersWebtoon(bool value) => _cropBordersWebtoon.update(value);

  void setCropBordersGaps(bool value) => _cropBordersGaps.update(value);

  void setSmoothAutoScroll(bool value) => _smoothAutoScroll.update(value);

  // Per-series-capable setters. perSeries=false is the "For this series" OFF
  // path (§2.6): set the app-wide default and drop this series' override.

  Future<void> setReaderMode(ReaderMode mode, {bool perSeries = true}) {
    if (perSeries) return _patchMeta(MangaMetaKeys.readerMode, mode.name);
    // "Default" is only meaningful per-series; globally it just means "no
    // override", so the global key is left alone.
    return _clearMetaThenWriteGlobal(
      MangaMetaKeys.readerMode,
      mode == ReaderMode.defaultReader
          ? null
          : () => _readerModeKey.update(mode),
    );
  }

  Future<void> setNavigationLayout(
    ReaderNavigationLayout layout, {
    bool perSeries = true,
  }) =>
      perSeries
          ? _patchMeta(MangaMetaKeys.readerNavigationLayout, layout.name)
          : _clearMetaThenWriteGlobal(
              MangaMetaKeys.readerNavigationLayout,
              () => _navigationLayoutKey.update(layout),
            );

  Future<void> setSidePadding(double value, {bool perSeries = true}) =>
      perSeries
          ? _patchMeta(MangaMetaKeys.readerPadding, value)
          : _clearMetaThenWriteGlobal(
              MangaMetaKeys.readerPadding,
              () => _readerPaddingKey.update(value),
            );

  Future<void> setMagnifierSize(double value, {bool perSeries = true}) =>
      perSeries
          ? _patchMeta(MangaMetaKeys.readerMagnifierSize, value)
          : _clearMetaThenWriteGlobal(
              MangaMetaKeys.readerMagnifierSize,
              () => _readerMagnifierSizeKey.update(value),
            );

  Future<void> setReaderOrientation(
    ReaderOrientation orientation, {
    bool perSeries = true,
  }) =>
      perSeries
          ? _patchMeta(MangaMetaKeys.readerOrientation, orientation.name)
          : _clearMetaThenWriteGlobal(
              MangaMetaKeys.readerOrientation,
              () => _readerOrientationKey.update(orientation),
            );

  /// Writes the NEW 4-value key only; the legacy invertTap bool is never
  /// destructively rewritten (compat read stays valid for a downgrade).
  Future<void> setTapInvert(TapInvert value, {bool perSeries = true}) =>
      perSeries
          ? _patchMeta(MangaMetaKeys.readerTapInvert, value.name)
          : _clearMetaThenWriteGlobal(
              MangaMetaKeys.readerTapInvert,
              () => _readerTapInvertKey.update(value),
            );

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

  /// Meta delete runs first while ref is still valid; the global write comes
  /// last since it rebuilds this model (captured notifier, no ref use after).
  Future<void> _clearMetaThenWriteGlobal(
    MangaMetaKeys key,
    void Function()? writeGlobal,
  ) async {
    final link = ref.keepAlive();
    try {
      await AsyncValue.guard(
        () => ref.read(mangaBookRepositoryProvider).deleteMangaMeta(
              mangaId: mangaId,
              key: key.key,
            ),
      );
      ref.invalidate(mangaWithIdProvider(mangaId: mangaId));
    } finally {
      link.close();
    }
    writeGlobal?.call();
  }
}

/// Plan-named alias for the resolved-settings family.
final readerEffectiveSettingsProvider = readerSettingsModelProvider;
