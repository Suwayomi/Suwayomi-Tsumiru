// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../settings/presentation/reader/widgets/reader_filter_prefs/reader_filter_prefs.dart';
import '../../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../../../../settings/presentation/reader/widgets/reader_invert_tap_tile/reader_invert_tap_tile.dart';
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

abstract final class ReaderSettings {
  /// Keep the Default sentinel here; the engine resolves the app-wide mode later.
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

  /// Reads the new key, then the legacy boolean (true means both); writes only the new key.
  static final tapInvert = ReaderSetting<TapInvert>(
    scope: ReaderSettingScope.perSeries,
    perSeriesKey: MangaMetaKeys.readerTapInvert,
    global: readerTapInvertCompatProvider,
    fallback: TapInvert.none,
  );

  // Migration-only keys; new zoom controls must use the paged/long-strip keys.
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

  static final pagedPinchToZoom = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: pagedPinchToZoomProvider,
    fallback: DBKeys.pagedPinchToZoom.initial as bool,
  );

  static final pagedDoubleTapToZoom = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: pagedDoubleTapToZoomProvider,
    fallback: DBKeys.pagedDoubleTapToZoom.initial as bool,
  );

  static final pagedDisableZoomOut = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: pagedDisableZoomOutProvider,
    fallback: DBKeys.pagedDisableZoomOut.initial as bool,
  );

  static final longStripPinchToZoom = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: longStripPinchToZoomProvider,
    fallback: DBKeys.longStripPinchToZoom.initial as bool,
  );

  static final longStripDoubleTapToZoom = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: longStripDoubleTapToZoomProvider,
    fallback: DBKeys.longStripDoubleTapToZoom.initial as bool,
  );

  static final longStripDisableZoomOut = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: longStripDisableZoomOutProvider,
    fallback: DBKeys.longStripDisableZoomOut.initial as bool,
  );

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

  static final dualPageSplitPaged = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: dualPageSplitPagedProvider,
    fallback: DBKeys.dualPageSplitPaged.initial as bool,
  );

  static final dualPageInvertPaged = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: dualPageInvertPagedProvider,
    fallback: DBKeys.dualPageInvertPaged.initial as bool,
  );

  static final rotateWidePages = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: rotateWidePagesProvider,
    fallback: DBKeys.rotateWidePages.initial as bool,
  );

  static final rotateWideInvert = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: rotateWideInvertProvider,
    fallback: DBKeys.rotateWideInvert.initial as bool,
  );

  static final trueDualPageSpread = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: trueDualPageSpreadProvider,
    fallback: DBKeys.trueDualPageSpread.initial as bool,
  );

  static final webtoonScaleType = ReaderSetting<WebtoonScaleType>(
    scope: ReaderSettingScope.global,
    global: webtoonScaleTypeKeyProvider,
    fallback: DBKeys.webtoonScaleType.initial as WebtoonScaleType,
  );

  static final longStripWidthLimitUsePixels = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: longStripWidthLimitUsePixelsProvider,
    fallback: DBKeys.longStripWidthLimitUsePixels.initial as bool,
  );

  static final longStripWidthLimitPercent = ReaderSetting<int>(
    scope: ReaderSettingScope.global,
    global: longStripWidthLimitPercentProvider,
    fallback: DBKeys.longStripWidthLimitPercent.initial as int,
  );

  static final longStripWidthLimitPx = ReaderSetting<int>(
    scope: ReaderSettingScope.global,
    global: longStripWidthLimitPxProvider,
    fallback: DBKeys.longStripWidthLimitPx.initial as int,
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

  static final readerScrollAmount = ReaderSetting<ReaderScrollAmount>(
    scope: ReaderSettingScope.global,
    global: readerScrollAmountKeyProvider,
    fallback: DBKeys.readerScrollAmount.initial as ReaderScrollAmount,
  );

  static final autoScrollIntervalSeconds = ReaderSetting<int>(
    scope: ReaderSettingScope.global,
    global: autoScrollIntervalSecondsProvider,
    fallback: DBKeys.autoScrollIntervalSeconds.initial as int,
  );

  static final autoAdvanceIntervalSeconds = ReaderSetting<int>(
    scope: ReaderSettingScope.global,
    global: autoAdvanceIntervalSecondsProvider,
    fallback: DBKeys.autoAdvanceIntervalSeconds.initial as int,
  );

  static final dualPageSplitWebtoon = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: dualPageSplitWebtoonProvider,
    fallback: DBKeys.dualPageSplitWebtoon.initial as bool,
  );

  static final dualPageInvertWebtoon = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: dualPageInvertWebtoonProvider,
    fallback: DBKeys.dualPageInvertWebtoon.initial as bool,
  );

  static final backgroundColor = ReaderSetting<ReaderBackgroundColor>(
    scope: ReaderSettingScope.global,
    global: readerBackgroundColorKeyProvider,
    fallback: DBKeys.readerBackgroundColor.initial as ReaderBackgroundColor,
  );

  static final showPageNumber = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: showPageNumberProvider,
    fallback: DBKeys.showPageNumber.initial as bool,
  );

  static final landscapeVerticalSeekbar = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: landscapeVerticalSeekbarProvider,
    fallback: DBKeys.landscapeVerticalSeekbar.initial as bool,
  );

  static final readerFullscreen = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: readerFullscreenProvider,
    fallback: DBKeys.readerFullscreen.initial as bool,
  );

  static final drawUnderCutout = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: drawUnderCutoutProvider,
    fallback: DBKeys.drawUnderCutout.initial as bool,
  );

  static final readWithLongTap = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: readWithLongTapProvider,
    fallback: DBKeys.readWithLongTap.initial as bool,
  );

  static final alwaysShowChapterTransition = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: alwaysShowChapterTransitionProvider,
    fallback: DBKeys.alwaysShowChapterTransition.initial as bool,
  );

  static final flashOnPageChange = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: flashOnPageChangeProvider,
    fallback: DBKeys.flashOnPageChange.initial as bool,
  );

  static final flashDuration = ReaderSetting<int>(
    scope: ReaderSettingScope.global,
    global: flashDurationProvider,
    fallback: DBKeys.flashDuration.initial as int,
  );

  static final flashPageInterval = ReaderSetting<int>(
    scope: ReaderSettingScope.global,
    global: flashPageIntervalProvider,
    fallback: DBKeys.flashPageInterval.initial as int,
  );

  static final flashColor = ReaderSetting<FlashColor>(
    scope: ReaderSettingScope.global,
    global: flashColorKeyProvider,
    fallback: DBKeys.flashColor.initial as FlashColor,
  );

  static final customBrightness = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: customBrightnessProvider,
    fallback: DBKeys.customBrightness.initial as bool,
  );

  static final customBrightnessValue = ReaderSetting<int>(
    scope: ReaderSettingScope.global,
    global: customBrightnessValueProvider,
    fallback: DBKeys.customBrightnessValue.initial as int,
  );

  static final customColorFilter = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: customColorFilterProvider,
    fallback: DBKeys.customColorFilter.initial as bool,
  );

  static final colorFilterValue = ReaderSetting<int>(
    scope: ReaderSettingScope.global,
    global: colorFilterValueProvider,
    fallback: DBKeys.colorFilterValue.initial as int,
  );

  static final colorFilterBlendMode = ReaderSetting<ColorFilterBlendMode>(
    scope: ReaderSettingScope.global,
    global: colorFilterBlendModeKeyProvider,
    fallback: DBKeys.colorFilterBlendMode.initial as ColorFilterBlendMode,
  );

  static final grayscale = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: grayscaleProvider,
    fallback: DBKeys.grayscale.initial as bool,
  );

  static final invertedColors = ReaderSetting<bool>(
    scope: ReaderSettingScope.global,
    global: invertedColorsProvider,
    fallback: DBKeys.invertedColors.initial as bool,
  );
}

@freezed
abstract class ReaderSettingsState with _$ReaderSettingsState {
  const factory ReaderSettingsState({
    required ReaderMode readerMode,
    required ReaderNavigationLayout navigationLayout,
    required double sidePadding,
    required bool invertTap,
    required ReaderOrientation readerOrientation,
    required TapInvert tapInvert,
    required bool pinchToZoom,
    required bool doubleTapToZoom,
    required bool disableZoomOut,
    required bool disableZoomIn,
    required bool pagedPinchToZoom,
    required bool pagedDoubleTapToZoom,
    required bool pagedDisableZoomOut,
    required bool longStripPinchToZoom,
    required bool longStripDoubleTapToZoom,
    required bool longStripDisableZoomOut,
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
    required bool dualPageSplitPaged,
    required bool dualPageInvertPaged,
    required bool rotateWidePages,
    required bool rotateWideInvert,
    required bool trueDualPageSpread,
    required WebtoonScaleType webtoonScaleType,
    required bool longStripWidthLimitUsePixels,
    required int longStripWidthLimitPercent,
    required int longStripWidthLimitPx,
    required bool cropBordersWebtoon,
    required bool cropBordersGaps,
    required bool smoothAutoScroll,
    required ReaderScrollAmount readerScrollAmount,
    required int autoScrollIntervalSeconds,
    required int autoAdvanceIntervalSeconds,
    required bool dualPageSplitWebtoon,
    required bool dualPageInvertWebtoon,
    required ReaderBackgroundColor backgroundColor,
    required bool showPageNumber,
    required bool landscapeVerticalSeekbar,
    required bool readerFullscreen,
    required bool drawUnderCutout,
    required bool readWithLongTap,
    required bool alwaysShowChapterTransition,
    required bool flashOnPageChange,
    required int flashDuration,
    required int flashPageInterval,
    required FlashColor flashColor,
    required bool customBrightness,
    required int customBrightnessValue,
    required bool customColorFilter,
    required int colorFilterValue,
    required ColorFilterBlendMode colorFilterBlendMode,
    required bool grayscale,
    required bool invertedColors,
  }) = _ReaderSettingsState;
}

/// Resolves per-series overrides over global settings for the settings sheet.
@riverpod
class ReaderSettingsModel extends _$ReaderSettingsModel {
  // Capture notifiers before global writes rebuild this model and invalidate its ref.
  late PinchToZoom _pinchToZoom;
  late DoubleTapToZoom _doubleTapToZoom;
  late DisableZoomOut _disableZoomOut;
  late DisableZoomIn _disableZoomIn;
  late PagedPinchToZoom _pagedPinchToZoom;
  late PagedDoubleTapToZoom _pagedDoubleTapToZoom;
  late PagedDisableZoomOut _pagedDisableZoomOut;
  late LongStripPinchToZoom _longStripPinchToZoom;
  late LongStripDoubleTapToZoom _longStripDoubleTapToZoom;
  late LongStripDisableZoomOut _longStripDisableZoomOut;
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
  late DualPageSplitPaged _dualPageSplitPaged;
  late DualPageInvertPaged _dualPageInvertPaged;
  late RotateWidePages _rotateWidePages;
  late RotateWideInvert _rotateWideInvert;
  late TrueDualPageSpread _trueDualPageSpread;
  late WebtoonScaleTypeKey _webtoonScaleType;
  late LongStripWidthLimitUsePixels _longStripWidthLimitUsePixels;
  late LongStripWidthLimitPercent _longStripWidthLimitPercent;
  late LongStripWidthLimitPx _longStripWidthLimitPx;
  late CropBordersWebtoon _cropBordersWebtoon;
  late CropBordersGaps _cropBordersGaps;
  late SmoothAutoScroll _smoothAutoScroll;
  late ReaderScrollAmountKey _readerScrollAmount;
  late AutoScrollIntervalSeconds _autoScrollIntervalSeconds;
  late AutoAdvanceIntervalSeconds _autoAdvanceIntervalSeconds;
  late DualPageSplitWebtoon _dualPageSplitWebtoon;
  late DualPageInvertWebtoon _dualPageInvertWebtoon;
  late ReaderBackgroundColorKey _backgroundColor;
  late ShowPageNumber _showPageNumber;
  late LandscapeVerticalSeekbar _landscapeVerticalSeekbar;
  late ReaderFullscreen _readerFullscreen;
  late DrawUnderCutout _drawUnderCutout;
  late ReadWithLongTap _readWithLongTap;
  late AlwaysShowChapterTransition _alwaysShowChapterTransition;
  late FlashOnPageChange _flashOnPageChange;
  late FlashDuration _flashDuration;
  late FlashPageInterval _flashPageInterval;
  late FlashColorKey _flashColor;
  late CustomBrightness _customBrightness;
  late CustomBrightnessValue _customBrightnessValue;
  late CustomColorFilter _customColorFilter;
  late ColorFilterValue _colorFilterValue;
  late ColorFilterBlendModeKey _colorFilterBlendMode;
  late Grayscale _grayscale;
  late InvertedColors _invertedColors;
  // Globals of the per-series fields, for the "For this series" OFF path.
  late ReaderModeKey _readerModeKey;
  late ReaderNavigationLayoutKey _navigationLayoutKey;
  late ReaderOrientationKey _readerOrientationKey;
  late ReaderTapInvertKey _readerTapInvertKey;
  late ReaderPaddingKey _readerPaddingKey;

  @override
  ReaderSettingsState build(int mangaId) {
    _pinchToZoom = ref.read(pinchToZoomProvider.notifier);
    _doubleTapToZoom = ref.read(doubleTapToZoomProvider.notifier);
    _disableZoomOut = ref.read(disableZoomOutProvider.notifier);
    _disableZoomIn = ref.read(disableZoomInProvider.notifier);
    _pagedPinchToZoom = ref.read(pagedPinchToZoomProvider.notifier);
    _pagedDoubleTapToZoom = ref.read(pagedDoubleTapToZoomProvider.notifier);
    _pagedDisableZoomOut = ref.read(pagedDisableZoomOutProvider.notifier);
    _longStripPinchToZoom = ref.read(longStripPinchToZoomProvider.notifier);
    _longStripDoubleTapToZoom =
        ref.read(longStripDoubleTapToZoomProvider.notifier);
    _longStripDisableZoomOut =
        ref.read(longStripDisableZoomOutProvider.notifier);
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
    _dualPageSplitPaged = ref.read(dualPageSplitPagedProvider.notifier);
    _dualPageInvertPaged = ref.read(dualPageInvertPagedProvider.notifier);
    _rotateWidePages = ref.read(rotateWidePagesProvider.notifier);
    _rotateWideInvert = ref.read(rotateWideInvertProvider.notifier);
    _trueDualPageSpread = ref.read(trueDualPageSpreadProvider.notifier);
    _webtoonScaleType = ref.read(webtoonScaleTypeKeyProvider.notifier);
    _longStripWidthLimitUsePixels =
        ref.read(longStripWidthLimitUsePixelsProvider.notifier);
    _longStripWidthLimitPercent =
        ref.read(longStripWidthLimitPercentProvider.notifier);
    _longStripWidthLimitPx = ref.read(longStripWidthLimitPxProvider.notifier);
    _cropBordersWebtoon = ref.read(cropBordersWebtoonProvider.notifier);
    _cropBordersGaps = ref.read(cropBordersGapsProvider.notifier);
    _smoothAutoScroll = ref.read(smoothAutoScrollProvider.notifier);
    _readerScrollAmount = ref.read(readerScrollAmountKeyProvider.notifier);
    _autoScrollIntervalSeconds =
        ref.read(autoScrollIntervalSecondsProvider.notifier);
    _autoAdvanceIntervalSeconds =
        ref.read(autoAdvanceIntervalSecondsProvider.notifier);
    _dualPageSplitWebtoon = ref.read(dualPageSplitWebtoonProvider.notifier);
    _dualPageInvertWebtoon = ref.read(dualPageInvertWebtoonProvider.notifier);
    _backgroundColor = ref.read(readerBackgroundColorKeyProvider.notifier);
    _showPageNumber = ref.read(showPageNumberProvider.notifier);
    _landscapeVerticalSeekbar =
        ref.read(landscapeVerticalSeekbarProvider.notifier);
    _readerFullscreen = ref.read(readerFullscreenProvider.notifier);
    _drawUnderCutout = ref.read(drawUnderCutoutProvider.notifier);
    _readWithLongTap = ref.read(readWithLongTapProvider.notifier);
    _alwaysShowChapterTransition =
        ref.read(alwaysShowChapterTransitionProvider.notifier);
    _flashOnPageChange = ref.read(flashOnPageChangeProvider.notifier);
    _flashDuration = ref.read(flashDurationProvider.notifier);
    _flashPageInterval = ref.read(flashPageIntervalProvider.notifier);
    _flashColor = ref.read(flashColorKeyProvider.notifier);
    _customBrightness = ref.read(customBrightnessProvider.notifier);
    _customBrightnessValue = ref.read(customBrightnessValueProvider.notifier);
    _customColorFilter = ref.read(customColorFilterProvider.notifier);
    _colorFilterValue = ref.read(colorFilterValueProvider.notifier);
    _colorFilterBlendMode = ref.read(colorFilterBlendModeKeyProvider.notifier);
    _grayscale = ref.read(grayscaleProvider.notifier);
    _invertedColors = ref.read(invertedColorsProvider.notifier);
    _readerModeKey = ref.read(readerModeKeyProvider.notifier);
    _navigationLayoutKey = ref.read(readerNavigationLayoutKeyProvider.notifier);
    _readerOrientationKey = ref.read(readerOrientationKeyProvider.notifier);
    _readerTapInvertKey = ref.read(readerTapInvertKeyProvider.notifier);
    _readerPaddingKey = ref.read(readerPaddingKeyProvider.notifier);
    final meta =
        ref.watch(mangaWithIdProvider(mangaId: mangaId)).value?.metaData;
    return ReaderSettingsState(
      readerMode: ReaderSettings.mode.resolveWith(ref, meta?.readerMode),
      navigationLayout: ReaderSettings.navigationLayout
          .resolveWith(ref, meta?.readerNavigationLayout),
      sidePadding:
          ReaderSettings.sidePadding.resolveWith(ref, meta?.readerPadding),
      invertTap: ReaderSettings.invertTap.resolveWith(ref, null),
      readerOrientation: ReaderSettings.readerOrientation
          .resolveWith(ref, meta?.readerOrientation),
      tapInvert:
          ReaderSettings.tapInvert.resolveWith(ref, meta?.readerTapInvert),
      pinchToZoom: ReaderSettings.pinchToZoom.resolveWith(ref, null),
      doubleTapToZoom: ReaderSettings.doubleTapToZoom.resolveWith(ref, null),
      disableZoomOut: ReaderSettings.disableZoomOut.resolveWith(ref, null),
      disableZoomIn: ReaderSettings.disableZoomIn.resolveWith(ref, null),
      pagedPinchToZoom:
          ReaderSettings.pagedPinchToZoom.resolveWith(ref, null),
      pagedDoubleTapToZoom:
          ReaderSettings.pagedDoubleTapToZoom.resolveWith(ref, null),
      pagedDisableZoomOut:
          ReaderSettings.pagedDisableZoomOut.resolveWith(ref, null),
      longStripPinchToZoom:
          ReaderSettings.longStripPinchToZoom.resolveWith(ref, null),
      longStripDoubleTapToZoom:
          ReaderSettings.longStripDoubleTapToZoom.resolveWith(ref, null),
      longStripDisableZoomOut:
          ReaderSettings.longStripDisableZoomOut.resolveWith(ref, null),
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
      dualPageSplitPaged:
          ReaderSettings.dualPageSplitPaged.resolveWith(ref, null),
      dualPageInvertPaged:
          ReaderSettings.dualPageInvertPaged.resolveWith(ref, null),
      rotateWidePages: ReaderSettings.rotateWidePages.resolveWith(ref, null),
      rotateWideInvert: ReaderSettings.rotateWideInvert.resolveWith(ref, null),
      trueDualPageSpread:
          ReaderSettings.trueDualPageSpread.resolveWith(ref, null),
      webtoonScaleType: ReaderSettings.webtoonScaleType.resolveWith(ref, null),
      longStripWidthLimitUsePixels:
          ReaderSettings.longStripWidthLimitUsePixels.resolveWith(ref, null),
      longStripWidthLimitPercent:
          ReaderSettings.longStripWidthLimitPercent.resolveWith(ref, null),
      longStripWidthLimitPx:
          ReaderSettings.longStripWidthLimitPx.resolveWith(ref, null),
      cropBordersWebtoon:
          ReaderSettings.cropBordersWebtoon.resolveWith(ref, null),
      cropBordersGaps: ReaderSettings.cropBordersGaps.resolveWith(ref, null),
      smoothAutoScroll: ReaderSettings.smoothAutoScroll.resolveWith(ref, null),
      readerScrollAmount:
          ReaderSettings.readerScrollAmount.resolveWith(ref, null),
      autoScrollIntervalSeconds:
          ReaderSettings.autoScrollIntervalSeconds.resolveWith(ref, null),
      autoAdvanceIntervalSeconds:
          ReaderSettings.autoAdvanceIntervalSeconds.resolveWith(ref, null),
      dualPageSplitWebtoon:
          ReaderSettings.dualPageSplitWebtoon.resolveWith(ref, null),
      dualPageInvertWebtoon:
          ReaderSettings.dualPageInvertWebtoon.resolveWith(ref, null),
      backgroundColor: ReaderSettings.backgroundColor.resolveWith(ref, null),
      showPageNumber: ReaderSettings.showPageNumber.resolveWith(ref, null),
      landscapeVerticalSeekbar:
          ReaderSettings.landscapeVerticalSeekbar.resolveWith(ref, null),
      readerFullscreen: ReaderSettings.readerFullscreen.resolveWith(ref, null),
      drawUnderCutout: ReaderSettings.drawUnderCutout.resolveWith(ref, null),
      readWithLongTap: ReaderSettings.readWithLongTap.resolveWith(ref, null),
      alwaysShowChapterTransition:
          ReaderSettings.alwaysShowChapterTransition.resolveWith(ref, null),
      flashOnPageChange:
          ReaderSettings.flashOnPageChange.resolveWith(ref, null),
      flashDuration: ReaderSettings.flashDuration.resolveWith(ref, null),
      flashPageInterval:
          ReaderSettings.flashPageInterval.resolveWith(ref, null),
      flashColor: ReaderSettings.flashColor.resolveWith(ref, null),
      customBrightness: ReaderSettings.customBrightness.resolveWith(ref, null),
      customBrightnessValue:
          ReaderSettings.customBrightnessValue.resolveWith(ref, null),
      customColorFilter:
          ReaderSettings.customColorFilter.resolveWith(ref, null),
      colorFilterValue: ReaderSettings.colorFilterValue.resolveWith(ref, null),
      colorFilterBlendMode:
          ReaderSettings.colorFilterBlendMode.resolveWith(ref, null),
      grayscale: ReaderSettings.grayscale.resolveWith(ref, null),
      invertedColors: ReaderSettings.invertedColors.resolveWith(ref, null),
    );
  }

  void setPinchToZoom(bool value) => _pinchToZoom.update(value);

  void setDoubleTapToZoom(bool value) => _doubleTapToZoom.update(value);

  void setDisableZoomOut(bool value) => _disableZoomOut.update(value);

  void setDisableZoomIn(bool value) => _disableZoomIn.update(value);

  void setPagedPinchToZoom(bool value) => _pagedPinchToZoom.update(value);

  void setPagedDoubleTapToZoom(bool value) =>
      _pagedDoubleTapToZoom.update(value);

  void setPagedDisableZoomOut(bool value) =>
      _pagedDisableZoomOut.update(value);

  void setLongStripPinchToZoom(bool value) =>
      _longStripPinchToZoom.update(value);

  void setLongStripDoubleTapToZoom(bool value) =>
      _longStripDoubleTapToZoom.update(value);

  void setLongStripDisableZoomOut(bool value) =>
      _longStripDisableZoomOut.update(value);

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

  void setLongStripWidthLimitUsePixels(bool value) =>
      _longStripWidthLimitUsePixels.update(value);

  void setLongStripWidthLimitPercent(int value) =>
      _longStripWidthLimitPercent.update(value.clamp(10, 100));

  void setLongStripWidthLimitPx(int value) =>
      _longStripWidthLimitPx.update(value.clamp(200, 2000));

  void setCropBordersWebtoon(bool value) => _cropBordersWebtoon.update(value);

  void setCropBordersGaps(bool value) => _cropBordersGaps.update(value);

  void setSmoothAutoScroll(bool value) => _smoothAutoScroll.update(value);

  void setReaderScrollAmount(ReaderScrollAmount value) =>
      _readerScrollAmount.update(value);

  void setAutoScrollIntervalSeconds(int value) =>
      _autoScrollIntervalSeconds.update(value);

  void setAutoAdvanceIntervalSeconds(int value) =>
      _autoAdvanceIntervalSeconds.update(value);

  void setDualPageSplitPaged(bool value) => _dualPageSplitPaged.update(value);

  void setDualPageInvertPaged(bool value) => _dualPageInvertPaged.update(value);

  void setRotateWidePages(bool value) => _rotateWidePages.update(value);

  void setRotateWideInvert(bool value) => _rotateWideInvert.update(value);

  void setTrueDualPageSpread(bool value) => _trueDualPageSpread.update(value);

  void setDualPageSplitWebtoon(bool value) =>
      _dualPageSplitWebtoon.update(value);

  void setDualPageInvertWebtoon(bool value) =>
      _dualPageInvertWebtoon.update(value);

  void setBackgroundColor(ReaderBackgroundColor value) =>
      _backgroundColor.update(value);

  void setShowPageNumber(bool value) => _showPageNumber.update(value);

  void setLandscapeVerticalSeekbar(bool value) =>
      _landscapeVerticalSeekbar.update(value);

  void setReaderFullscreen(bool value) => _readerFullscreen.update(value);

  void setDrawUnderCutout(bool value) => _drawUnderCutout.update(value);

  void setReadWithLongTap(bool value) => _readWithLongTap.update(value);

  void setAlwaysShowChapterTransition(bool value) =>
      _alwaysShowChapterTransition.update(value);

  void setFlashOnPageChange(bool value) => _flashOnPageChange.update(value);

  void setFlashDuration(int value) => _flashDuration.update(value);

  void setFlashPageInterval(int value) => _flashPageInterval.update(value);

  void setFlashColor(FlashColor value) => _flashColor.update(value);

  void setCustomBrightness(bool value) => _customBrightness.update(value);

  void setCustomBrightnessValue(int value) =>
      _customBrightnessValue.update(value);

  void setCustomColorFilter(bool value) => _customColorFilter.update(value);

  void setColorFilterValue(int value) => _colorFilterValue.update(value);

  void setColorFilterBlendMode(ColorFilterBlendMode value) =>
      _colorFilterBlendMode.update(value);

  void setGrayscale(bool value) => _grayscale.update(value);

  void setInvertedColors(bool value) => _invertedColors.update(value);

  // With perSeries=false, remove the override and update the app-wide default.

  Future<void> setReaderMode(ReaderMode mode, {bool perSeries = true}) {
    if (perSeries) return _patchMeta(MangaMetaKeys.readerMode, mode.name);
    // Default only has meaning per-series; leave the global key unchanged.
    return _clearMetaThenWriteGlobal(
      MangaMetaKeys.readerMode,
      mode == ReaderMode.defaultReader
          ? null
          : () => _readerModeKey.update(mode),
    );
  }

  /// The global branch targets an unused legacy key; global controls must use paged/long-strip keys.
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

  /// Write only the new tap-invert key so legacy reads remain valid after downgrade.
  Future<void> setTapInvert(TapInvert value, {bool perSeries = true}) =>
      perSeries
          ? _patchMeta(MangaMetaKeys.readerTapInvert, value.name)
          : _clearMetaThenWriteGlobal(
              MangaMetaKeys.readerTapInvert,
              () => _readerTapInvertKey.update(value),
            );

  Future<void> _patchMeta(MangaMetaKeys key, dynamic value) async {
    // Hold the provider across writes so dismissing the sheet cannot dispose ref before invalidation.
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

  /// Delete meta before the global write rebuilds this model; do not use ref afterwards.
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

final readerEffectiveSettingsProvider = readerSettingsModelProvider;
