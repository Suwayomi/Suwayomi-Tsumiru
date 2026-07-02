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

import '../../../../constants/db_keys.dart';
import '../../../../constants/enum.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import 'widgets/reader_feedback_toasts_tile/reader_feedback_toasts_tile.dart';
import 'widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import 'widgets/reader_general_prefs/reader_general_prefs.dart';
import 'widgets/reader_ignore_safe_area_tile/reader_ignore_safe_area_tile.dart';
import 'widgets/reader_infinity_scrolling_mode_tile/reader_infinity_scrolling_mode_tile.dart';
import 'widgets/reader_initial_overlay_tile/reader_initial_overlay_tile.dart';
import 'widgets/reader_invert_tap_tile/reader_invert_tap_tile.dart';
import 'widgets/reader_keep_screen_on_tile/reader_keep_screen_on_tile.dart';
import 'widgets/reader_last_page_swipe_tile/reader_last_page_swipe_tile.dart';
import 'widgets/reader_left_handed_seekbar_tile/reader_left_handed_seekbar_tile.dart';
import 'widgets/reader_magnifier_size_slider/reader_magnifier_size_slider.dart';
import 'widgets/reader_mode_tile/reader_mode_tile.dart';
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

/// Global reader defaults (Komikku SettingsReaderScreen). A few of these settings
/// can be overridden per-manga from the in-reader sheet's "For this series"
/// block; the rest apply to every series.
class ReaderSettingsScreen extends ConsumerWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVolumeTapEnabled = ref.watch(volumeTapProvider).ifNull();
    final forceHorizontal =
        ref.watch(forceHorizontalSeekbarProvider).ifNull(false);
    final fullscreen = ref.watch(readerFullscreenProvider).ifNull(true);
    final flash = ref.watch(flashOnPageChangeProvider).ifNull(false);
    final splitPaged = ref.watch(dualPageSplitPagedProvider).ifNull(false);
    final rotateWide = ref.watch(rotateWidePagesProvider).ifNull(false);

    T? enumOf<T>(ProviderListenable<T?> p) => ref.watch(p);
    void Function(T?) setEnum<T>(Refreshable<dynamic> notifier) =>
        (v) => (ref.read(notifier) as dynamic).update(v);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.reader)),
      body: ListView(
        children: [
          // ── General ──
          const ReaderModeTile(),
          const ReaderNavigationLayoutTile(),
          const ReaderInvertTapTile(),
          _EnumChips<ReaderBackgroundColor>(
            label: context.l10n.readerBackgroundColor,
            values: const [
              ReaderBackgroundColor.black,
              ReaderBackgroundColor.gray,
              ReaderBackgroundColor.white,
              ReaderBackgroundColor.automatic,
            ],
            selected: enumOf(readerBackgroundColorKeyProvider) ??
                ReaderBackgroundColor.black,
            labelOf: (v) => v.toLocale(context),
            onSelected: setEnum(readerBackgroundColorKeyProvider.notifier),
          ),
          _BoolTile(
            title: context.l10n.showPageNumber,
            value: ref.watch(showPageNumberProvider).ifNull(true),
            onChanged: ref.read(showPageNumberProvider.notifier).update,
          ),
          const ReaderInitialOverlayTile(),
          const SwipeChapterToggleTile(),
          const ReaderLastPageSwipeTile(),
          const ReaderInfinityScrollingModeTile(),
          const ReaderScrollAnimationTile(),
          const ReaderFeedbackToastsTile(),
          _BoolTile(
            title: context.l10n.forceHorizontalSeekbar,
            value: forceHorizontal,
            onChanged: ref.read(forceHorizontalSeekbarProvider.notifier).update,
          ),
          if (!forceHorizontal) ...[
            _BoolTile(
              indent: true,
              title: context.l10n.showVerticalSeekbarInLandscape,
              value:
                  ref.watch(landscapeVerticalSeekbarProvider).ifNull(false),
              onChanged:
                  ref.read(landscapeVerticalSeekbarProvider.notifier).update,
            ),
            _BoolTile(
              indent: true,
              title: context.l10n.leftHandedVerticalSeekbar,
              value:
                  ref.watch(leftHandedVerticalSeekbarProvider).ifNull(false),
              onChanged:
                  ref.read(leftHandedVerticalSeekbarProvider.notifier).update,
            ),
          ],
          _BoolTile(
            title: context.l10n.readerFullscreen,
            value: fullscreen,
            onChanged: ref.read(readerFullscreenProvider.notifier).update,
          ),
          if (fullscreen)
            _BoolTile(
              indent: true,
              title: context.l10n.showContentInCutoutArea,
              value: ref.watch(drawUnderCutoutProvider).ifNull(true),
              onChanged: ref.read(drawUnderCutoutProvider.notifier).update,
            ),
          _BoolTile(
            title: context.l10n.showActionsOnLongTap,
            value: ref.watch(readWithLongTapProvider).ifNull(true),
            onChanged: ref.read(readWithLongTapProvider.notifier).update,
          ),
          _BoolTile(
            title: context.l10n.alwaysShowChapterTransition,
            value: ref.watch(alwaysShowChapterTransitionProvider).ifNull(true),
            onChanged:
                ref.read(alwaysShowChapterTransitionProvider.notifier).update,
          ),
          _BoolTile(
            title: context.l10n.flashOnPageChange,
            value: flash,
            onChanged: ref.read(flashOnPageChangeProvider.notifier).update,
          ),
          if (flash) ...[
            _IntSliderTile(
              title: context.l10n.flashDuration,
              value: ref.watch(flashDurationProvider) ??
                  (DBKeys.flashDuration.initial as int),
              min: 1,
              max: 15,
              labelOf: (v) => context.l10n.flashDurationMs(v * kFlashMsPerTick),
              onChanged: ref.read(flashDurationProvider.notifier).update,
            ),
            _IntSliderTile(
              title: context.l10n.flashEvery,
              value: ref.watch(flashPageIntervalProvider) ??
                  (DBKeys.flashPageInterval.initial as int),
              min: 1,
              max: 10,
              labelOf: (v) => context.l10n.flashEveryPages(v),
              onChanged: ref.read(flashPageIntervalProvider.notifier).update,
            ),
            _EnumChips<FlashColor>(
              label: context.l10n.flashWith,
              values: FlashColor.values,
              selected: enumOf(flashColorKeyProvider) ?? FlashColor.values.first,
              labelOf: (v) => v.toLocale(context),
              onSelected: setEnum(flashColorKeyProvider.notifier),
            ),
          ],
          const ReaderPaddingSlider(),
          const ReaderMagnifierSizeSlider(),
          if (!kIsWeb) ...[
            if (Platform.isAndroid || Platform.isIOS) ...[
              const ReaderKeepScreenOnTile(),
              const ReaderIgnoreSafeAreaTile(),
            ],
            if (Platform.isAndroid) ...[
              const ReaderVolumeTapTile(),
              if (isVolumeTapEnabled) const ReaderVolumeTapInvertTile(),
            ],
          ],

          // ── Pager viewer defaults ──
          _Header(context.l10n.readerGroupPagerViewer),
          _EnumChips<ImageScaleType>(
            label: context.l10n.imageScaleType,
            values: ImageScaleType.values,
            selected:
                enumOf(imageScaleTypeKeyProvider) ?? ImageScaleType.fitScreen,
            labelOf: (v) => v.toLocale(context),
            onSelected: setEnum(imageScaleTypeKeyProvider.notifier),
          ),
          _EnumChips<PageLayout>(
            label: context.l10n.pageLayout,
            values: PageLayout.values,
            selected: enumOf(pageLayoutKeyProvider) ?? PageLayout.automatic,
            labelOf: (v) => v.toLocale(context),
            onSelected: setEnum(pageLayoutKeyProvider.notifier),
          ),
          _EnumChips<CenterMarginType>(
            label: context.l10n.centerMarginType,
            values: CenterMarginType.values,
            selected:
                enumOf(centerMarginTypeKeyProvider) ?? CenterMarginType.none,
            labelOf: (v) => v.toLocale(context),
            onSelected: setEnum(centerMarginTypeKeyProvider.notifier),
          ),
          _BoolTile(
            title: context.l10n.smallerTapZones,
            value: ref.watch(smallerTapZonesProvider).ifNull(false),
            onChanged: ref.read(smallerTapZonesProvider.notifier).update,
          ),
          _BoolTile(
            title: context.l10n.cropBorders,
            value: ref.watch(cropBordersProvider).ifNull(false),
            onChanged: ref.read(cropBordersProvider.notifier).update,
          ),
          _BoolTile(
            title: context.l10n.splitWidePages,
            value: splitPaged,
            onChanged: ref.read(dualPageSplitPagedProvider.notifier).update,
          ),
          if (splitPaged)
            _BoolTile(
              indent: true,
              title: context.l10n.invertSplitPagesPlacement,
              value: ref.watch(dualPageInvertPagedProvider).ifNull(false),
              onChanged: ref.read(dualPageInvertPagedProvider.notifier).update,
            ),
          _BoolTile(
            title: context.l10n.rotateWidePagesToFit,
            value: rotateWide,
            onChanged: ref.read(rotateWidePagesProvider.notifier).update,
          ),
          if (rotateWide)
            _BoolTile(
              indent: true,
              title: context.l10n.invertWidePageRotation,
              value: ref.watch(rotateWideInvertProvider).ifNull(false),
              onChanged: ref.read(rotateWideInvertProvider.notifier).update,
            ),
          _BoolTile(
            title: context.l10n.animatePageTransitions,
            value: ref.watch(animatePageTransitionsProvider).ifNull(true),
            onChanged: ref.read(animatePageTransitionsProvider.notifier).update,
          ),
          _BoolTile(
            title: context.l10n.invertDoublePages,
            value: ref.watch(invertDoublePagesProvider).ifNull(false),
            onChanged: ref.read(invertDoublePagesProvider.notifier).update,
          ),
          _BoolTile(
            title: context.l10n.dualPageSpreadInLandscape,
            value: ref.watch(trueDualPageSpreadProvider).ifNull(false),
            onChanged: ref.read(trueDualPageSpreadProvider.notifier).update,
          ),
          _BoolTile(
            title: context.l10n.doubleTapToZoom,
            value: ref.watch(doubleTapToZoomProvider).ifNull(true),
            onChanged: ref.read(doubleTapToZoomProvider.notifier).update,
          ),
          const ReaderPinchToZoom(),
          _BoolTile(
            title: context.l10n.disableZoomIn,
            value: ref.watch(disableZoomInProvider).ifNull(false),
            onChanged: ref.read(disableZoomInProvider.notifier).update,
          ),
          _BoolTile(
            title: context.l10n.disableZoomOut,
            value: ref.watch(disableZoomOutProvider).ifNull(false),
            onChanged: ref.read(disableZoomOutProvider.notifier).update,
          ),

          // ── Long strip viewer defaults ──
          _Header(context.l10n.readerGroupWebtoonViewer),
          _EnumChips<WebtoonScaleType>(
            label: context.l10n.webtoonScaleType,
            values: WebtoonScaleType.values,
            selected:
                enumOf(webtoonScaleTypeKeyProvider) ?? WebtoonScaleType.fitScreen,
            labelOf: (v) => v.toLocale(context),
            onSelected: setEnum(webtoonScaleTypeKeyProvider.notifier),
          ),
          _BoolTile(
            title: context.l10n.cropBorders,
            value: ref.watch(cropBordersWebtoonProvider).ifNull(false),
            onChanged: ref.read(cropBordersWebtoonProvider.notifier).update,
          ),

          const Gap(128),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            text,
            style: context.theme.textTheme.titleSmall?.copyWith(
              color: context.theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
      contentPadding:
          indent ? const EdgeInsetsDirectional.only(start: 32, end: 16) : null,
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
              style: context.theme.textTheme.labelLarge?.copyWith(
                color: context.theme.colorScheme.primary,
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
