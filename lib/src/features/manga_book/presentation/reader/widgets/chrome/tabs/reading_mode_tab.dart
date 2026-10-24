// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../constants/enum.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../../widgets/compact_switch.dart';
import '../../../../../../settings/presentation/reader/widgets/long_strip_width_limit_slider/long_strip_width_limit_slider.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_auto_webtoon_mode/reader_auto_webtoon_mode.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import '../../../../manga_details/controller/manga_details_controller.dart';
import '../../../controller/auto_webtoon.dart';
import '../../../controller/reader_mode_adapter.dart';
import '../../../controller/reader_settings_model.dart';
import '../../../utils/reader_mode_kind.dart';
import 'int_slider_tile.dart';

class ReadingModeTab extends ConsumerWidget {
  const ReadingModeTab({
    super.key,
    required this.mangaId,
    required this.readerPadding,
  });

  final int mangaId;
  final ValueNotifier<double> readerPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Settings under "For this series" always write per-manga overrides.
    const perSeries = true;
    final settings = ref.watch(readerSettingsModelProvider(mangaId));
    final model = ref.read(readerSettingsModelProvider(mangaId).notifier);
    final manga = ref.watch(mangaWithIdProvider(mangaId: mangaId)).value;
    final autoMode = manga == null
        ? null
        : sessionAutoReaderMode(
            enabled: ref.watch(autoWebtoonModeProvider).ifNull(true),
            seriesMode: settings.readerMode,
            genres: manga.genre,
            sourceName: manga.source?.name,
          );
    final resolvedMode =
        autoMode ??
        (settings.readerMode == ReaderMode.defaultReader
            ? (ref.watch(readerModeKeyProvider) ??
                  ReaderMode.singleHorizontalRTL)
            : settings.readerMode);
    final isLongStrip = switch (resolvedMode) {
      ReaderMode.webtoon ||
      ReaderMode.continuousVertical ||
      ReaderMode.continuousHorizontalLTR ||
      ReaderMode.continuousHorizontalRTL => true,
      _ => false,
    };
    final storedChip = ReaderModeAdapter.toChip(settings.readerMode);
    final resolvedNav = effectiveNavigationLayout(
      ref,
      mode: resolvedMode,
      seriesOverride: settings.navigationLayout,
    );

    // I7: own scroll view; never the sheet's controller.
    return ListView(
      primary: false,
      children: [
        _GroupHeading(context.l10n.readerForThisSeries),
        _SectionLabel(context.l10n.readerSectionReadingMode),
        _ChipRow(
          children: [
            for (final chip in ReadingModeChip.values)
              FilterChip(
                selected: storedChip == chip,
                showCheckmark: false,
                label: Text(chip.toLocale(context)),
                onSelected: (_) => model.setReaderMode(
                  ReaderModeAdapter.fromChip(chip),
                  perSeries: perSeries,
                ),
              ),
            if (storedChip == null)
              FilterChip(
                selected: true,
                showCheckmark: false,
                label: Text(context.l10n.readerModeChipLegacyContinuous),
                onSelected: (_) {},
              ),
          ],
        ),
        _SectionLabel(context.l10n.readerSectionRotation),
        _ChipRow(
          children: [
            for (final orientation in ReaderOrientation.values)
              FilterChip(
                selected: settings.readerOrientation == orientation,
                showCheckmark: false,
                label: Text(orientation.toLocale(context)),
                onSelected: (_) => model.setReaderOrientation(
                  orientation,
                  perSeries: perSeries,
                ),
              ),
          ],
        ),
        _SectionLabel(context.l10n.readerSectionTapZones),
        _ChipRow(
          children: [
            for (final layout in ReaderNavigationLayout.displayOrder)
              FilterChip(
                selected: settings.navigationLayout == layout,
                showCheckmark: false,
                label: Text(layout.toLocale(context)),
                onSelected: (_) =>
                    model.setNavigationLayout(layout, perSeries: perSeries),
              ),
          ],
        ),
        if (resolvedNav != ReaderNavigationLayout.disabled) ...[
          _SectionLabel(context.l10n.readerSectionTapInvert),
          _ChipRow(
            children: [
              for (final invert in TapInvert.values)
                FilterChip(
                  selected: settings.tapInvert == invert,
                  showCheckmark: false,
                  label: Text(invert.toLocale(context)),
                  onSelected: (_) =>
                      model.setTapInvert(invert, perSeries: perSeries),
                ),
            ],
          ),
        ],
        AsyncReaderPaddingSlider(
          readerPadding: readerPadding,
          onChanged: (value) =>
              model.setSidePadding(value, perSeries: perSeries),
        ),
        _GroupHeading(
          isLongStrip
              ? context.l10n.readerGroupWebtoonViewer
              : context.l10n.readerGroupPagerViewer,
        ),
        AnimatedSwitcher(
          duration: context.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          child: isLongStrip
              ? _LongStripSection(
                  key: const ValueKey('longStrip'),
                  mangaId: mangaId,
                  showGapsSettings:
                      resolvedMode == ReaderMode.continuousVertical,
                )
              : _PagedSection(key: const ValueKey('paged'), mangaId: mangaId),
        ),
      ],
    );
  }
}

class _PagedSection extends ConsumerWidget {
  const _PagedSection({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsModelProvider(mangaId));
    final model = ref.read(readerSettingsModelProvider(mangaId).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(context.l10n.imageScaleType),
        _ChipRow(
          children: [
            for (final scale in ImageScaleType.values)
              FilterChip(
                selected: settings.imageScaleType == scale,
                showCheckmark: false,
                label: Text(scale.toLocale(context)),
                onSelected: (_) => model.setImageScaleType(scale),
              ),
          ],
        ),
        _SectionLabel(context.l10n.pageLayout),
        _ChipRow(
          children: [
            for (final layout in PageLayout.values)
              FilterChip(
                selected: settings.pageLayout == layout,
                showCheckmark: false,
                label: Text(layout.toLocale(context)),
                onSelected: (_) => model.setPageLayout(layout),
              ),
          ],
        ),
        _SectionLabel(context.l10n.centerMarginType),
        _ChipRow(
          children: [
            for (final margin in CenterMarginType.values)
              FilterChip(
                selected: settings.centerMarginType == margin,
                showCheckmark: false,
                label: Text(margin.toLocale(context)),
                onSelected: (_) => model.setCenterMarginType(margin),
              ),
          ],
        ),
        IntSliderTile(
          title: context.l10n.autoAdvanceInterval,
          valueLabel: context.l10n.autoScrollSeconds(
            settings.autoAdvanceIntervalSeconds,
          ),
          value: settings.autoAdvanceIntervalSeconds,
          min: 1,
          max: 30,
          onChanged: model.setAutoAdvanceIntervalSeconds,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.smallerTapZones),
          value: settings.smallerTapZones,
          onChanged: model.setSmallerTapZones,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.cropBorders),
          value: settings.cropBorders,
          onChanged: model.setCropBorders,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.splitWidePages),
          value: settings.dualPageSplitPaged,
          onChanged: model.setDualPageSplitPaged,
        ),
        if (settings.dualPageSplitPaged)
          _SubSwitchTile(
            title: context.l10n.invertSplitPagesPlacement,
            value: settings.dualPageInvertPaged,
            onChanged: model.setDualPageInvertPaged,
          ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.rotateWidePagesToFit),
          value: settings.rotateWidePages,
          onChanged: model.setRotateWidePages,
        ),
        if (settings.rotateWidePages)
          _SubSwitchTile(
            title: context.l10n.invertWidePageRotation,
            value: settings.rotateWideInvert,
            onChanged: model.setRotateWideInvert,
          ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.animatePageTransitions),
          value: settings.animatePageTransitions,
          onChanged: model.setAnimatePageTransitions,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.invertDoublePages),
          value: settings.invertDoublePages,
          onChanged: model.setInvertDoublePages,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.dualPageSpreadInLandscape),
          value: settings.trueDualPageSpread,
          onChanged: model.setTrueDualPageSpread,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.doubleTapToZoom),
          value: settings.pagedDoubleTapToZoom,
          onChanged: model.setPagedDoubleTapToZoom,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.pinchToZoom),
          value: settings.pagedPinchToZoom,
          onChanged: model.setPagedPinchToZoom,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.disableZoomIn),
          value: settings.disableZoomIn,
          onChanged: model.setDisableZoomIn,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.disableZoomOut),
          value: settings.pagedDisableZoomOut,
          onChanged: model.setPagedDisableZoomOut,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.navigateToPan),
          value: settings.navigateToPan,
          onChanged: model.setNavigateToPan,
        ),
      ],
    );
  }
}

class _LongStripSection extends ConsumerWidget {
  const _LongStripSection({
    super.key,
    required this.mangaId,
    required this.showGapsSettings,
  });

  final int mangaId;
  final bool showGapsSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsModelProvider(mangaId));
    final model = ref.read(readerSettingsModelProvider(mangaId).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(context.l10n.webtoonScaleType),
        _ChipRow(
          children: [
            for (final scale in WebtoonScaleType.values)
              FilterChip(
                selected: settings.webtoonScaleType == scale,
                showCheckmark: false,
                label: Text(scale.toLocale(context)),
                onSelected: (_) => model.setWebtoonScaleType(scale),
              ),
          ],
        ),
        LongStripWidthLimitSlider(
          // Greyed under Original size: native-size pages never widen, so a
          // width cap has nothing to do.
          enabled: settings.webtoonScaleType != WebtoonScaleType.originalSize,
          usePixels: settings.longStripWidthLimitUsePixels,
          percent: settings.longStripWidthLimitPercent,
          px: settings.longStripWidthLimitPx,
          onUnitChanged: model.setLongStripWidthLimitUsePixels,
          onPercentCommitted: model.setLongStripWidthLimitPercent,
          onPxCommitted: model.setLongStripWidthLimitPx,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.smallerTapZones),
          value: settings.smallerTapZones,
          onChanged: model.setSmallerTapZones,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.cropBorders),
          value: settings.cropBordersWebtoon,
          onChanged: model.setCropBordersWebtoon,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.smoothAutoScroll),
          value: settings.smoothAutoScroll,
          onChanged: model.setSmoothAutoScroll,
        ),
        IntSliderTile(
          title: context.l10n.autoScrollInterval,
          valueLabel: context.l10n.autoScrollSeconds(
            settings.autoScrollIntervalSeconds,
          ),
          value: settings.autoScrollIntervalSeconds,
          min: 1,
          max: 30,
          onChanged: model.setAutoScrollIntervalSeconds,
        ),
        _SectionLabel(context.l10n.scrollAmount),
        _ChipRow(
          children: [
            for (final amount in ReaderScrollAmount.values)
              FilterChip(
                selected: settings.readerScrollAmount == amount,
                showCheckmark: false,
                label: Text(amount.toLocale(context)),
                onSelected: (_) => model.setReaderScrollAmount(amount),
              ),
          ],
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.animatePageTransitions),
          value: settings.animatePageTransitions,
          onChanged: model.setAnimatePageTransitions,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.doubleTapToZoom),
          value: settings.longStripDoubleTapToZoom,
          onChanged: model.setLongStripDoubleTapToZoom,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.pinchToZoom),
          value: settings.longStripPinchToZoom,
          onChanged: model.setLongStripPinchToZoom,
        ),
        CompactSwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.disableZoomOut),
          value: settings.longStripDisableZoomOut,
          onChanged: model.setLongStripDisableZoomOut,
        ),
        if (showGapsSettings) ...[
          _SectionLabel(context.l10n.readerModeChipLongStripGaps),
          CompactSwitchListTile(
            controlAffinity: ListTileControlAffinity.trailing,
            title: Text(context.l10n.cropBorders),
            value: settings.cropBordersGaps,
            onChanged: model.setCropBordersGaps,
          ),
        ],
      ],
    );
  }
}

class _SubSwitchTile extends StatelessWidget {
  const _SubSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CompactSwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 16),
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            text,
            style: context.theme.textTheme.titleSmall?.copyWith(
              color: context.theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: context.theme.textTheme.labelLarge?.copyWith(
            color: context.theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(spacing: 8, runSpacing: 4, children: children),
    );
  }
}
