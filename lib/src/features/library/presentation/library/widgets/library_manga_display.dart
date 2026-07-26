// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/custom_checkbox_list_tile.dart';
import '../../../../../widgets/manga_cover/providers/manga_cover_providers.dart';
import '../../../../../widgets/organizer_heading.dart';
import '../controller/library_controller.dart';

class LibraryMangaDisplay extends ConsumerWidget {
  const LibraryMangaDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final selectedMode =
        displayMode ?? DBKeys.libraryDisplayMode.initial as DisplayMode;
    final isGridMode = selectedMode.isGrid;

    final currentCols = (isLandscape
            ? ref.watch(libraryLandscapeColumnsProvider)
            : ref.watch(libraryPortraitColumnsProvider)) ??
        0;

    final gridStyle =
        ref.watch(libraryGridStyleKeyProvider) ?? LibraryGridStyle.uniform;
    final listScale = ref.watch(libraryListScaleProvider) ??
        DBKeys.listScale.initial as double;

    return ListView(
      shrinkWrap: true,
      children: [
        OrganizerHeading(context.l10n.displayMode),
        // A chip row for display mode, not a tall radio list — keeps
        // the sheet compact.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final mode in DisplayMode.libraryDisplayList)
                FilterChip(
                  selected: selectedMode == mode,
                  showCheckmark: false,
                  label: Text(mode.toLibraryLocale(context)),
                  onSelected: (_) => ref
                      .read(libraryDisplayModeProvider.notifier)
                      .update(mode),
                ),
            ],
          ),
        ),
        if (isGridMode) ...[
          OrganizerHeading(isLandscape
              ? context.l10n.libraryColumnsLandscape
              : context.l10n.libraryColumnsPortrait),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                const Icon(Icons.grid_view_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: currentCols.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: currentCols == 0 ? 'Auto' : '$currentCols',
                    onChanged: (val) => isLandscape
                        ? ref
                            .read(libraryLandscapeColumnsProvider.notifier)
                            .update(val.round())
                        : ref
                            .read(libraryPortraitColumnsProvider.notifier)
                            .update(val.round()),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    currentCols == 0 ? 'Auto' : '$currentCols',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
          OrganizerHeading(context.l10n.gridStyle),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final style in LibraryGridStyle.values)
                  FilterChip(
                    selected: gridStyle == style,
                    showCheckmark: false,
                    avatar: Icon(style.icon, size: 18),
                    label: Text(style.toLocale(context)),
                    onSelected: (_) => ref
                        .read(libraryGridStyleKeyProvider.notifier)
                        .update(style),
                  ),
              ],
            ),
          ),
        ],
        if (!isGridMode) ...[
          OrganizerHeading(context.l10n.listSize),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                const Icon(Icons.format_size_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: listScale,
                    min: 0.7,
                    max: 1.6,
                    divisions: 18,
                    label: '${(listScale * 100).round()}%',
                    onChanged: (val) => ref
                        .read(libraryListScaleProvider.notifier)
                        .update(double.parse(val.toStringAsFixed(2))),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${(listScale * 100).round()}%',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ],
        // Only modes that draw the title on the theme surface, where an
        // uncapped title can push its own row taller. The compact grid is out:
        // its title sits on the art, so growing it would swallow the cover.
        if (selectedMode == DisplayMode.comfortableGrid ||
            selectedMode == DisplayMode.list ||
            selectedMode == DisplayMode.descriptiveList)
          CustomCheckboxListTile(
            title: context.l10n.limitTitleLines,
            provider: limitTitleLinesProvider,
            onChanged: ref.read(limitTitleLinesProvider.notifier).update,
          ),
        CustomCheckboxListTile(
          title: context.l10n.outlineOnCovers,
          provider: outlineOnCoversProvider,
          onChanged: ref.read(outlineOnCoversProvider.notifier).update,
        ),
      ],
    );
  }
}
