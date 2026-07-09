// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../constants/enum.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_magnifier_size_slider/reader_magnifier_size_slider.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_navigation_layout_tile/reader_navigation_layout_tile.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_padding_slider/reader_padding_slider.dart';
import '../../../controller/reader_mode_adapter.dart';
import '../../../controller/reader_settings_model.dart';

/// Reading-mode tab: chip rows for the common settings,
/// then a paged / long-strip section swapped on the resolved mode.
class ReadingModeTab extends ConsumerWidget {
  const ReadingModeTab({
    super.key,
    required this.mangaId,
    required this.readerPadding,
    required this.magnifierSize,
  });

  final int mangaId;
  final ValueNotifier<double> readerPadding;
  final ValueNotifier<double> magnifierSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The settings under the "For this series" heading are
    // ALWAYS per-manga overrides; the viewer/global settings below are global
    // defaults. There is no scope toggle.
    const perSeries = true;
    final settings = ref.watch(readerSettingsModelProvider(mangaId));
    final model = ref.read(readerSettingsModelProvider(mangaId).notifier);
    // "Default" dereferences the app-wide mode, mirroring reader_screen.
    final resolvedMode = settings.readerMode == ReaderMode.defaultReader
        ? (ref.watch(readerModeKeyProvider) ?? ReaderMode.webtoon)
        : settings.readerMode;
    final isLongStrip = switch (resolvedMode) {
      ReaderMode.webtoon ||
      ReaderMode.continuousVertical ||
      ReaderMode.continuousHorizontalLTR ||
      ReaderMode.continuousHorizontalRTL =>
        true,
      _ => false,
    };
    // The stored mode's chip; null for the legacy continuous-horizontal
    // orphans, which get their own honest extra chip (§2.5).
    final storedChip = ReaderModeAdapter.toChip(settings.readerMode);
    final resolvedNav =
        settings.navigationLayout == ReaderNavigationLayout.defaultNavigation
            ? (ref.watch(readerNavigationLayoutKeyProvider) ??
                ReaderNavigationLayout.defaultNavigation)
            : settings.navigationLayout;

    // I7: own scroll view; never the sheet's controller.
    return ListView(
      primary: false,
      children: [
        // ── For this series (per-manga overrides) ──
        _GroupHeading(context.l10n.readerForThisSeries),
        _SectionLabel(context.l10n.readerSectionReadingMode),
        _ChipRow(
          children: [
            for (final chip in ReadingModeChip.values)
              FilterChip(
                selected: storedChip == chip,
                showCheckmark: false,
                label: Text(chip.toLocale(context)),
                // The ONLY write path for mode — orphans stay stored until a
                // parity chip is tapped (§2.5).
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
            for (final layout in ReaderNavigationLayout.values)
              FilterChip(
                selected: settings.navigationLayout == layout,
                showCheckmark: false,
                label: Text(layout.toLocale(context)),
                onSelected: (_) => model.setNavigationLayout(
                  layout,
                  perSeries: perSeries,
                ),
              ),
          ],
        ),
        // Inverting tap zones is meaningless while they're disabled, so the
        // row is hidden.
        if (resolvedNav != ReaderNavigationLayout.disabled) ...[
          _SectionLabel(context.l10n.readerSectionTapInvert),
          _ChipRow(
            children: [
              for (final invert in TapInvert.values)
                FilterChip(
                  selected: settings.tapInvert == invert,
                  showCheckmark: false,
                  label: Text(invert.toLocale(context)),
                  onSelected: (_) => model.setTapInvert(
                    invert,
                    perSeries: perSeries,
                  ),
                ),
            ],
          ),
        ],
        // Padding + magnifier are per-manga overrides too, so they live under
        // "For this series", not the global viewer block.
        AsyncReaderPaddingSlider(
          readerPadding: readerPadding,
          onChanged: (value) =>
              model.setSidePadding(value, perSeries: perSeries),
        ),
        AsyncReaderMagnifierSizeSlider(
          readerMagnifierSize: magnifierSize,
          onChanged: (value) =>
              model.setMagnifierSize(value, perSeries: perSeries),
        ),
        // ── Viewer defaults (global, apply to every series) ──
        _GroupHeading(isLongStrip
            ? context.l10n.readerGroupWebtoonViewer
            : context.l10n.readerGroupPagerViewer),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isLongStrip
              ? _LongStripSection(
                  key: const ValueKey('longStrip'),
                  mangaId: mangaId,
                  showGapsSettings:
                      resolvedMode == ReaderMode.continuousVertical,
                )
              : _PagedSection(
                  key: const ValueKey('paged'),
                  mangaId: mangaId,
                ),
        ),
      ],
    );
  }
}

/// Paged-only settings. All fields are global
/// prefs.
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
        _SectionLabel(context.l10n.readerSectionPaged),
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
        // Zoom start is tied to landscape auto-zoom, which paged mode does not
        // apply automatically.
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
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.smallerTapZones),
          value: settings.smallerTapZones,
          onChanged: model.setSmallerTapZones,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.cropBorders),
          value: settings.cropBorders,
          onChanged: model.setCropBorders,
        ),
        // Landscape auto-zoom stays out of paged mode; wide manga spreads
        // should open fitted and let the reader choose when to zoom.
        SwitchListTile(
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
        SwitchListTile(
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
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.animatePageTransitions),
          value: settings.animatePageTransitions,
          onChanged: model.setAnimatePageTransitions,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.invertDoublePages),
          value: settings.invertDoublePages,
          onChanged: model.setInvertDoublePages,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.dualPageSpreadInLandscape),
          value: settings.trueDualPageSpread,
          onChanged: model.setTrueDualPageSpread,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.doubleTapToZoom),
          value: settings.doubleTapToZoom,
          onChanged: model.setDoubleTapToZoom,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.pinchToZoom),
          value: settings.pinchToZoom,
          onChanged: model.setPinchToZoom,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.disableZoomOut),
          value: settings.disableZoomOut,
          onChanged: model.setDisableZoomOut,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.navigateToPan),
          value: settings.navigateToPan,
          onChanged: model.setNavigateToPan,
        ),
      ],
    );
  }
}

/// Long-strip settings, incl. the legacy
/// continuous-horizontal orphans; gaps sub-settings only for that mode.
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
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.smallerTapZones),
          value: settings.smallerTapZones,
          onChanged: model.setSmallerTapZones,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.cropBorders),
          value: settings.cropBordersWebtoon,
          onChanged: model.setCropBordersWebtoon,
        ),
        // smoothAutoScroll hidden: no auto-scroll driver exists yet (a webtoon
        // auto-advance feature); see docs/architecture/reader.md.
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.animatePageTransitions),
          value: settings.animatePageTransitions,
          onChanged: model.setAnimatePageTransitions,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.doubleTapToZoom),
          value: settings.doubleTapToZoom,
          onChanged: model.setDoubleTapToZoom,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.pinchToZoom),
          value: settings.pinchToZoom,
          onChanged: model.setPinchToZoom,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.disableZoomOut),
          value: settings.disableZoomOut,
          onChanged: model.setDisableZoomOut,
        ),
        // Webtoon split-wide hidden: splitting one strip page into two entries
        // needs a page-list remap in the frozen webtoon engine; see reader.md.
        if (showGapsSettings) ...[
          _SectionLabel(context.l10n.readerModeChipLongStripGaps),
          SwitchListTile(
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

/// Indented dependent toggle, shown only while its parent switch is ON.
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
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 16),
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A top-level group header — separates the "For this
/// series" per-manga block from the global "Viewer defaults" block so scope is
/// unambiguous.
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
              fontWeight: FontWeight.w700,
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

/// Single-select chip row.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: children,
      ),
    );
  }
}
