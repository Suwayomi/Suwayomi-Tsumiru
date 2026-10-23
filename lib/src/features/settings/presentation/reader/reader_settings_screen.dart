// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';

import '../../../../constants/db_keys.dart';
import '../../../../constants/enum.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/platform/platform_runtime.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import 'widgets/long_strip_width_limit_slider/long_strip_width_limit_slider.dart';
import 'widgets/reader_feedback_toasts_tile/reader_feedback_toasts_tile.dart';
import 'widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import 'widgets/reader_general_prefs/reader_general_prefs.dart';
import 'widgets/reader_ignore_safe_area_tile/reader_ignore_safe_area_tile.dart';
import 'widgets/reader_initial_overlay_tile/reader_initial_overlay_tile.dart';
import 'widgets/reader_keep_screen_on_tile/reader_keep_screen_on_tile.dart';
import 'widgets/reader_last_page_swipe_tile/reader_last_page_swipe_tile.dart';
import 'widgets/reader_left_handed_seekbar_tile/reader_left_handed_seekbar_tile.dart';
import 'widgets/reader_mode_tile/reader_mode_tile.dart';
import 'widgets/reader_mouse_scroll_speed_slider/reader_mouse_scroll_speed_slider.dart';
import 'widgets/reader_navigation_layout_tile/reader_navigation_layout_tile.dart';
import 'widgets/reader_padding_slider/reader_padding_slider.dart';
import 'widgets/reader_paged_prefs/reader_paged_prefs.dart';
import 'widgets/reader_pinch_to_zoom/reader_pinch_to_zoom.dart';
import 'widgets/reader_scroll_animation_tile/reader_scroll_animation_tile.dart';
import 'widgets/reader_swipe_toggle_tile/reader_swipe_chapter_toggle_tile.dart';
import 'widgets/reader_volume_tap_invert_tile/reader_volume_tap_invert_tile.dart';
import 'widgets/reader_volume_tap_tile/reader_volume_tap_tile.dart';
import 'widgets/reader_webtoon_prefs/reader_webtoon_prefs.dart';
import 'widgets/reader_zoom_toggles/reader_zoom_toggles.dart';
import 'widgets/tap_zones_overlay/tap_zones_overlay.dart';

/// Global reader defaults. A few of these settings
/// can be overridden per-manga from the in-reader sheet's "For this series"
/// block; the rest apply to every series.
class ReaderSettingsScreen extends ConsumerWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVolumeTapEnabled = ref.watch(volumeTapProvider).ifNull();
    final forceHorizontal = ref
        .watch(forceHorizontalSeekbarProvider)
        .ifNull(false);
    final fullscreen = ref.watch(readerFullscreenProvider).ifNull(true);
    final flash = ref.watch(flashOnPageChangeProvider).ifNull(false);
    final splitPaged = ref.watch(dualPageSplitPagedProvider).ifNull(false);
    final rotateWide = ref.watch(rotateWidePagesProvider).ifNull(false);
    final disableZoomIn = ref.watch(disableZoomInProvider).ifNull(false);
    final showVolumeKeys = !kIsWeb && isAndroidRuntime;
    final showNavigation = showVolumeKeys || isKeyboardRuntime;

    T? enumOf<T>(ProviderListenable<T?> p) => ref.watch(p);
    void Function(T?) setEnum<T>(Refreshable<dynamic> notifier) =>
        (v) => (ref.read(notifier) as dynamic).update(v);

    // Native desktop draws the toolbar in the shell bar instead of an app
    // bar.
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.reader);
    final scaffold = Scaffold(
      appBar: topBar ? null : AppBar(title: title),
      body: SettingsHighlightScope(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              children: [
                // Group order follows Komikku's reader settings: ungrouped
                // basics first, then Display, E-Ink, Reading, Paged,
                // Long strip, Navigation, Actions.
                const SizedBox(height: 16),
                const SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'readerMode',
                      child: ReaderModeTile(),
                    ),
                    // Tap zones and their inversion are per viewer, so they
                    // live in the Paged and Long strip groups below — same as
                    // Komikku. Only the overlay and the zone size are shared.
                    SettingsHighlightTarget(
                      id: 'showTapZonesOverlay',
                      child: ShowTapZonesOverlayTile(),
                    ),
                    SettingsHighlightTarget(
                      id: 'smallerTapZones',
                      child: _SmallerTapZonesTile(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'forceHorizontalSeekbar',
                      child: _BoolTile(
                        title: context.l10n.forceHorizontalSeekbar,
                        value: forceHorizontal,
                        onChanged: ref
                            .read(forceHorizontalSeekbarProvider.notifier)
                            .update,
                      ),
                    ),
                    if (!forceHorizontal) ...[
                      SettingsHighlightTarget(
                        id: 'showVerticalSeekbar',
                        child: _BoolTile(
                          indent: true,
                          title: context.l10n.showVerticalSeekbarInLandscape,
                          value: ref
                              .watch(landscapeVerticalSeekbarProvider)
                              .ifNull(false),
                          onChanged: ref
                              .read(landscapeVerticalSeekbarProvider.notifier)
                              .update,
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'leftHandedVerticalSeekbar',
                        child: _BoolTile(
                          indent: true,
                          title: context.l10n.leftHandedVerticalSeekbar,
                          value: ref
                              .watch(leftHandedVerticalSeekbarProvider)
                              .ifNull(false),
                          onChanged: ref
                              .read(leftHandedVerticalSeekbarProvider.notifier)
                              .update,
                        ),
                      ),
                    ],
                  ],
                ),

                // ── Display ──
                SettingsGroupHeading(label: context.l10n.readerGroupDisplay),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'readerBackgroundColor',
                      child: _EnumChips<ReaderBackgroundColor>(
                        label: context.l10n.readerBackgroundColor,
                        values: const [
                          ReaderBackgroundColor.black,
                          ReaderBackgroundColor.gray,
                          ReaderBackgroundColor.white,
                          ReaderBackgroundColor.automatic,
                        ],
                        selected:
                            enumOf(readerBackgroundColorKeyProvider) ??
                            ReaderBackgroundColor.black,
                        labelOf: (v) => v.toLocale(context),
                        onSelected: setEnum(
                          readerBackgroundColorKeyProvider.notifier,
                        ),
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'readerFullscreen',
                      child: _BoolTile(
                        title: context.l10n.readerFullscreen,
                        value: fullscreen,
                        onChanged: ref
                            .read(readerFullscreenProvider.notifier)
                            .update,
                      ),
                    ),
                    if (fullscreen)
                      SettingsHighlightTarget(
                        id: 'showContentInCutoutArea',
                        child: _BoolTile(
                          indent: true,
                          title: context.l10n.showContentInCutoutArea,
                          value: ref
                              .watch(drawUnderCutoutProvider)
                              .ifNull(true),
                          onChanged: ref
                              .read(drawUnderCutoutProvider.notifier)
                              .update,
                        ),
                      ),
                    if (!kIsWeb && (isAndroidRuntime || Platform.isIOS))
                      const SettingsHighlightTarget(
                        id: 'ignoreSafeArea',
                        child: ReaderIgnoreSafeAreaTile(),
                      ),
                    // Not long-strip only: reader_wrapper pads whichever axis
                    // you are not scrolling, so paged reading uses it too.
                    const SettingsHighlightTarget(
                      id: 'readerPadding',
                      child: ReaderPaddingSlider(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    if (!kIsWeb && (isAndroidRuntime || Platform.isIOS))
                      const SettingsHighlightTarget(
                        id: 'keepScreenOn',
                        child: ReaderKeepScreenOnTile(),
                      ),
                    SettingsHighlightTarget(
                      id: 'showPageNumber',
                      child: _BoolTile(
                        title: context.l10n.showPageNumber,
                        value: ref.watch(showPageNumberProvider).ifNull(true),
                        onChanged: ref
                            .read(showPageNumberProvider.notifier)
                            .update,
                      ),
                    ),
                    const SettingsHighlightTarget(
                      id: 'readerOverlay',
                      child: ReaderInitialOverlayTile(),
                    ),
                  ],
                ),

                // ── E-Ink ──
                SettingsGroupHeading(label: context.l10n.readerGroupEInk),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'flashOnPageChange',
                      child: _BoolTile(
                        title: context.l10n.flashOnPageChange,
                        value: flash,
                        onChanged: ref
                            .read(flashOnPageChangeProvider.notifier)
                            .update,
                      ),
                    ),
                    if (flash) ...[
                      SettingsHighlightTarget(
                        id: 'flashDuration',
                        child: _IntSliderTile(
                          title: context.l10n.flashDuration,
                          value:
                              ref.watch(flashDurationProvider) ??
                              (DBKeys.flashDuration.initial as int),
                          min: 1,
                          max: 15,
                          labelOf: (v) =>
                              context.l10n.flashDurationMs(v * kFlashMsPerTick),
                          onChanged: ref
                              .read(flashDurationProvider.notifier)
                              .update,
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'flashEvery',
                        child: _IntSliderTile(
                          title: context.l10n.flashEvery,
                          value:
                              ref.watch(flashPageIntervalProvider) ??
                              (DBKeys.flashPageInterval.initial as int),
                          min: 1,
                          max: 10,
                          labelOf: (v) => context.l10n.flashEveryPages(v),
                          onChanged: ref
                              .read(flashPageIntervalProvider.notifier)
                              .update,
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'flashWith',
                        child: _EnumChips<FlashColor>(
                          label: context.l10n.flashWith,
                          values: FlashColor.values,
                          selected:
                              enumOf(flashColorKeyProvider) ??
                              FlashColor.values.first,
                          labelOf: (v) => v.toLocale(context),
                          onSelected: setEnum(flashColorKeyProvider.notifier),
                        ),
                      ),
                    ],
                  ],
                ),

                // ── Reading ──
                SettingsGroupHeading(label: context.l10n.readerGroupReading),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'alwaysShowChapterTransition',
                      child: _BoolTile(
                        title: context.l10n.alwaysShowChapterTransition,
                        value: ref
                            .watch(alwaysShowChapterTransitionProvider)
                            .ifNull(true),
                        onChanged: ref
                            .read(alwaysShowChapterTransitionProvider.notifier)
                            .update,
                      ),
                    ),
                    const SettingsHighlightTarget(
                      id: 'swipeChapterToggle',
                      child: SwipeChapterToggleTile(),
                    ),
                    const SettingsHighlightTarget(
                      id: 'lastPageSwipe',
                      child: ReaderLastPageSwipeTile(),
                    ),
                    const SettingsHighlightTarget(
                      id: 'scrollAnimation',
                      child: ReaderScrollAnimationTile(),
                    ),
                    const SettingsHighlightTarget(
                      id: 'feedbackToasts',
                      child: ReaderFeedbackToastsTile(),
                    ),
                  ],
                ),

                // ── Paged ──
                SettingsGroupHeading(
                  label: context.l10n.readerGroupPagerViewer,
                ),
                const SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'pagedTapZones',
                      child: ReaderNavigationLayoutTile(longStrip: false),
                    ),
                    SettingsHighlightTarget(
                      id: 'pagedTapInvert',
                      child: ReaderTapInvertTile(longStrip: false),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'imageScaleType',
                      child: _EnumChips<ImageScaleType>(
                        label: context.l10n.imageScaleType,
                        values: ImageScaleType.values,
                        selected:
                            enumOf(imageScaleTypeKeyProvider) ??
                            ImageScaleType.fitScreen,
                        labelOf: (v) => v.toLocale(context),
                        onSelected: setEnum(imageScaleTypeKeyProvider.notifier),
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'pageLayout',
                      child: _EnumChips<PageLayout>(
                        label: context.l10n.pageLayout,
                        values: PageLayout.values,
                        selected:
                            enumOf(pageLayoutKeyProvider) ??
                            PageLayout.automatic,
                        labelOf: (v) => v.toLocale(context),
                        onSelected: setEnum(pageLayoutKeyProvider.notifier),
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'centerMarginType',
                      child: _EnumChips<CenterMarginType>(
                        label: context.l10n.centerMarginType,
                        values: CenterMarginType.values,
                        selected:
                            enumOf(centerMarginTypeKeyProvider) ??
                            CenterMarginType.none,
                        labelOf: (v) => v.toLocale(context),
                        onSelected: setEnum(
                          centerMarginTypeKeyProvider.notifier,
                        ),
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'cropBordersPaged',
                      child: _BoolTile(
                        title: context.l10n.cropBorders,
                        value: ref.watch(cropBordersProvider).ifNull(false),
                        onChanged: ref
                            .read(cropBordersProvider.notifier)
                            .update,
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'animatePageTransitions',
                      child: _BoolTile(
                        title: context.l10n.animatePageTransitions,
                        value: ref
                            .watch(animatePageTransitionsProvider)
                            .ifNull(true),
                        onChanged: ref
                            .read(animatePageTransitionsProvider.notifier)
                            .update,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'pagedDoubleTapToZoom',
                      child: _BoolTile(
                        title: context.l10n.doubleTapToZoom,
                        value: ref
                            .watch(pagedDoubleTapToZoomProvider)
                            .ifNull(true),
                        onChanged: ref
                            .read(pagedDoubleTapToZoomProvider.notifier)
                            .update,
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'pagedPinchToZoom',
                      child: _BoolTile(
                        title: context.l10n.pinchToZoom,
                        value: ref.watch(pagedPinchToZoomProvider).ifNull(true),
                        onChanged: ref
                            .read(pagedPinchToZoomProvider.notifier)
                            .update,
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'disableZoomIn',
                      child: _BoolTile(
                        title: context.l10n.disableZoomIn,
                        value: disableZoomIn,
                        onChanged: ref
                            .read(disableZoomInProvider.notifier)
                            .update,
                      ),
                    ),
                    // Both stay editable while zoom-in is off. The viewport
                    // already ignores them in that state, and greying them out
                    // would strand whatever value they were left on.
                    SettingsHighlightTarget(
                      id: 'pagedDisableZoomOut',
                      child: _BoolTile(
                        title: context.l10n.disableZoomOut,
                        value: ref
                            .watch(pagedDisableZoomOutProvider)
                            .ifNull(false),
                        onChanged: ref
                            .read(pagedDisableZoomOutProvider.notifier)
                            .update,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'splitWidePages',
                      child: _BoolTile(
                        title: context.l10n.splitWidePages,
                        value: splitPaged,
                        onChanged: ref
                            .read(dualPageSplitPagedProvider.notifier)
                            .update,
                      ),
                    ),
                    if (splitPaged)
                      SettingsHighlightTarget(
                        id: 'invertSplitPages',
                        child: _BoolTile(
                          indent: true,
                          title: context.l10n.invertSplitPagesPlacement,
                          value: ref
                              .watch(dualPageInvertPagedProvider)
                              .ifNull(false),
                          onChanged: ref
                              .read(dualPageInvertPagedProvider.notifier)
                              .update,
                        ),
                      ),
                    SettingsHighlightTarget(
                      id: 'rotateWidePages',
                      child: _BoolTile(
                        title: context.l10n.rotateWidePagesToFit,
                        value: rotateWide,
                        onChanged: ref
                            .read(rotateWidePagesProvider.notifier)
                            .update,
                      ),
                    ),
                    if (rotateWide)
                      SettingsHighlightTarget(
                        id: 'invertWidePageRotation',
                        child: _BoolTile(
                          indent: true,
                          title: context.l10n.invertWidePageRotation,
                          value: ref
                              .watch(rotateWideInvertProvider)
                              .ifNull(false),
                          onChanged: ref
                              .read(rotateWideInvertProvider.notifier)
                              .update,
                        ),
                      ),
                    SettingsHighlightTarget(
                      id: 'dualPageSpread',
                      child: _BoolTile(
                        title: context.l10n.dualPageSpreadInLandscape,
                        value: ref
                            .watch(trueDualPageSpreadProvider)
                            .ifNull(false),
                        onChanged: ref
                            .read(trueDualPageSpreadProvider.notifier)
                            .update,
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'invertDoublePages',
                      child: _BoolTile(
                        title: context.l10n.invertDoublePages,
                        value: ref
                            .watch(invertDoublePagesProvider)
                            .ifNull(false),
                        onChanged: ref
                            .read(invertDoublePagesProvider.notifier)
                            .update,
                      ),
                    ),
                  ],
                ),

                // ── Long strip ──
                SettingsGroupHeading(
                  label: context.l10n.readerGroupWebtoonViewer,
                ),
                const SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'longStripTapZones',
                      child: ReaderNavigationLayoutTile(longStrip: true),
                    ),
                    SettingsHighlightTarget(
                      id: 'longStripTapInvert',
                      child: ReaderTapInvertTile(longStrip: true),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'webtoonScaleType',
                      child: _EnumChips<WebtoonScaleType>(
                        label: context.l10n.webtoonScaleType,
                        values: WebtoonScaleType.values,
                        selected:
                            enumOf(webtoonScaleTypeKeyProvider) ??
                            WebtoonScaleType.fitScreen,
                        labelOf: (v) => v.toLocale(context),
                        onSelected: setEnum(
                          webtoonScaleTypeKeyProvider.notifier,
                        ),
                      ),
                    ),
                    // Greyed under Original size: native-size pages never
                    // widen, so a width cap has nothing to do.
                    SettingsHighlightTarget(
                      id: 'longStripWidthLimit',
                      child: LongStripWidthLimitSlider(
                        enabled:
                            (enumOf(webtoonScaleTypeKeyProvider) ??
                                WebtoonScaleType.fitScreen) !=
                            WebtoonScaleType.originalSize,
                        usePixels: ref
                            .watch(longStripWidthLimitUsePixelsProvider)
                            .ifNull(),
                        percent:
                            ref.watch(longStripWidthLimitPercentProvider) ??
                            DBKeys.longStripWidthLimitPercent.initial as int,
                        px:
                            ref.watch(longStripWidthLimitPxProvider) ??
                            DBKeys.longStripWidthLimitPx.initial as int,
                        onUnitChanged: ref
                            .read(longStripWidthLimitUsePixelsProvider.notifier)
                            .update,
                        // Clamped like the model setters, so every write path
                        // guards.
                        onPercentCommitted: (v) => ref
                            .read(longStripWidthLimitPercentProvider.notifier)
                            .update(v.clamp(10, 100)),
                        onPxCommitted: (v) => ref
                            .read(longStripWidthLimitPxProvider.notifier)
                            .update(v.clamp(200, 2000)),
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'cropBordersLongStrip',
                      child: _BoolTile(
                        title: context.l10n.cropBorders,
                        value: ref
                            .watch(cropBordersWebtoonProvider)
                            .ifNull(false),
                        onChanged: ref
                            .read(cropBordersWebtoonProvider.notifier)
                            .update,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'longStripDoubleTapToZoom',
                      child: _BoolTile(
                        title: context.l10n.doubleTapToZoom,
                        value: ref
                            .watch(longStripDoubleTapToZoomProvider)
                            .ifNull(true),
                        onChanged: ref
                            .read(longStripDoubleTapToZoomProvider.notifier)
                            .update,
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'longStripPinchToZoom',
                      child: _BoolTile(
                        title: context.l10n.pinchToZoom,
                        value: ref
                            .watch(longStripPinchToZoomProvider)
                            .ifNull(true),
                        onChanged: ref
                            .read(longStripPinchToZoomProvider.notifier)
                            .update,
                      ),
                    ),
                    SettingsHighlightTarget(
                      id: 'longStripDisableZoomOut',
                      child: _BoolTile(
                        title: context.l10n.disableZoomOut,
                        value: ref
                            .watch(longStripDisableZoomOutProvider)
                            .ifNull(false),
                        onChanged: ref
                            .read(longStripDisableZoomOutProvider.notifier)
                            .update,
                      ),
                    ),
                  ],
                ),

                // ── Navigation ──
                if (showNavigation) ...[
                  SettingsGroupHeading(
                    label: context.l10n.readerGroupNavigation,
                  ),
                  SettingsGroupCard(
                    children: [
                      if (showVolumeKeys) ...[
                        const SettingsHighlightTarget(
                          id: 'volumeTap',
                          child: ReaderVolumeTapTile(),
                        ),
                        if (isVolumeTapEnabled)
                          const SettingsHighlightTarget(
                            id: 'volumeTapInvert',
                            child: ReaderVolumeTapInvertTile(),
                          ),
                      ],
                      // Moved here from Reading; same keyboard-runtime gate.
                      if (isKeyboardRuntime)
                        const SettingsHighlightTarget(
                          id: 'mouseScrollSpeed',
                          child: ReaderMouseScrollSpeedSlider(),
                        ),
                    ],
                  ),
                ],

                // ── Actions ──
                SettingsGroupHeading(label: context.l10n.readerGroupActions),
                SettingsGroupCard(
                  children: [
                    SettingsHighlightTarget(
                      id: 'showActionsOnLongTap',
                      child: _BoolTile(
                        title: context.l10n.showActionsOnLongTap,
                        value: ref.watch(readWithLongTapProvider).ifNull(true),
                        onChanged: ref
                            .read(readWithLongTapProvider.notifier)
                            .update,
                      ),
                    ),
                  ],
                ),

                const Gap(128),
              ],
            ),
          ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}

class _SmallerTapZonesTile extends ConsumerWidget {
  const _SmallerTapZonesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _BoolTile(
      title: context.l10n.smallerTapZones,
      value: ref.watch(smallerTapZonesProvider).ifNull(false),
      onChanged: ref.read(smallerTapZonesProvider.notifier).update,
    );
  }
}

class _BoolTile extends StatelessWidget {
  const _BoolTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.indent = false,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      contentPadding: indent
          ? const EdgeInsetsDirectional.only(start: 32, end: 16)
          : null,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _EnumChips<T> extends StatelessWidget {
  const _EnumChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              label,
              style:
                  context.theme.listTileTheme.titleTextStyle ??
                  context.textTheme.titleMedium?.copyWith(
                    color: context.theme.colorScheme.onSurface,
                  ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final v in values)
                FilterChip(
                  selected: v == selected,
                  showCheckmark: false,
                  label: Text(labelOf(v)),
                  onSelected: (_) => onSelected(v),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IntSliderTile extends StatelessWidget {
  const _IntSliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.labelOf,
    required this.onChanged,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final String Function(int) labelOf;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Row(
        children: [
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: labelOf(value),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          Text(labelOf(value)),
        ],
      ),
    );
  }
}
