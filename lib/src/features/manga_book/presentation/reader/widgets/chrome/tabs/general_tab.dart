// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../constants/enum.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_auto_webtoon_mode/reader_auto_webtoon_mode.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_keep_screen_on_tile/reader_keep_screen_on_tile.dart';
import '../../../../../../settings/presentation/reader/widgets/reader_left_handed_seekbar_tile/reader_left_handed_seekbar_tile.dart';
import '../../../controller/reader_settings_model.dart';
import 'int_slider_tile.dart';

/// General tab: background color,
/// page number, seekbar chain, fullscreen, keep-screen-on, long-tap actions,
/// chapter transition, flash-on-page-change, Auto Webtoon Mode.
class GeneralTab extends ConsumerWidget {
  const GeneralTab({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsModelProvider(mangaId));
    final model = ref.read(readerSettingsModelProvider(mangaId).notifier);
    // Pre-existing globals not folded into the settings model.
    final forceHorizontal =
        ref.watch(forceHorizontalSeekbarProvider).ifNull(false);
    final leftHanded =
        ref.watch(leftHandedVerticalSeekbarProvider).ifNull(false);
    final keepScreenOn = ref.watch(keepScreenOnProvider).ifNull(true);
    final autoWebtoon = ref.watch(autoWebtoonModeProvider).ifNull(true);

    // I7: own scroll view; never the sheet's controller.
    return ListView(
      primary: false,
      children: [
        _SectionLabel(context.l10n.readerBackgroundColor),
        // Chip order is the UI order, not the stored-int order.
        _ChipRow(
          children: [
            for (final bg in const [
              ReaderBackgroundColor.black,
              ReaderBackgroundColor.gray,
              ReaderBackgroundColor.white,
              ReaderBackgroundColor.automatic,
            ])
              FilterChip(
                selected: settings.backgroundColor == bg,
                showCheckmark: false,
                label: Text(bg.toLocale(context)),
                onSelected: (_) => model.setBackgroundColor(bg),
              ),
          ],
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.showPageNumber),
          value: settings.showPageNumber,
          onChanged: model.setShowPageNumber,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.forceHorizontalSeekbar),
          value: forceHorizontal,
          onChanged: ref.read(forceHorizontalSeekbarProvider.notifier).update,
        ),
        if (!forceHorizontal) ...[
          _SubSwitchTile(
            title: context.l10n.showVerticalSeekbarInLandscape,
            value: settings.landscapeVerticalSeekbar,
            onChanged: model.setLandscapeVerticalSeekbar,
          ),
          _SubSwitchTile(
            title: context.l10n.leftHandedVerticalSeekbar,
            value: leftHanded,
            onChanged:
                ref.read(leftHandedVerticalSeekbarProvider.notifier).update,
          ),
        ],
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.readerFullscreen),
          value: settings.readerFullscreen,
          onChanged: model.setReaderFullscreen,
        ),
        if (settings.readerFullscreen)
          _SubSwitchTile(
            title: context.l10n.showContentInCutoutArea,
            value: settings.drawUnderCutout,
            onChanged: model.setDrawUnderCutout,
          ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.readerKeepScreenOn),
          value: keepScreenOn,
          onChanged: ref.read(keepScreenOnProvider.notifier).update,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.showActionsOnLongTap),
          value: settings.readWithLongTap,
          onChanged: model.setReadWithLongTap,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.alwaysShowChapterTransition),
          value: settings.alwaysShowChapterTransition,
          onChanged: model.setAlwaysShowChapterTransition,
        ),
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.flashOnPageChange),
          value: settings.flashOnPageChange,
          onChanged: model.setFlashOnPageChange,
        ),
        if (settings.flashOnPageChange) ...[
          IntSliderTile(
            title: context.l10n.flashDuration,
            valueLabel: context.l10n.flashDurationMs(
              settings.flashDuration * kFlashMsPerTick,
            ),
            value: settings.flashDuration,
            min: 1,
            max: 15,
            onChanged: model.setFlashDuration,
          ),
          IntSliderTile(
            title: context.l10n.flashEvery,
            valueLabel:
                context.l10n.flashEveryPages(settings.flashPageInterval),
            value: settings.flashPageInterval,
            min: 1,
            max: 10,
            onChanged: model.setFlashPageInterval,
          ),
          _SectionLabel(context.l10n.flashWith),
          _ChipRow(
            children: [
              for (final color in FlashColor.values)
                FilterChip(
                  selected: settings.flashColor == color,
                  showCheckmark: false,
                  label: Text(color.toLocale(context)),
                  onSelected: (_) => model.setFlashColor(color),
                ),
            ],
          ),
        ],
        SwitchListTile(
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(context.l10n.autoWebtoonMode),
          subtitle: Text(context.l10n.autoWebtoonModeSubtitle),
          value: autoWebtoon,
          onChanged: ref.read(autoWebtoonModeProvider.notifier).update,
        ),
      ],
    );
  }
}

/// Indented dependent toggle, shown only while its parent condition holds.
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
