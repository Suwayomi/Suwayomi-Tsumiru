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
import '../controller/library_controller.dart';

class LibraryMangaDisplay extends ConsumerWidget {
  const LibraryMangaDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    // Whether the current display mode uses a grid (slider is relevant).
    final isGridMode = displayMode == DisplayMode.grid ||
        displayMode == DisplayMode.coverOnly;

    final currentCols = (isLandscape
            ? ref.watch(libraryLandscapeColumnsProvider)
            : ref.watch(libraryPortraitColumnsProvider)) ??
        0;

    final selectedMode = displayMode ?? DBKeys.libraryDisplayMode.initial;

    return ListView(
      shrinkWrap: true,
      children: [
        _Heading(context.l10n.displayMode),
        // A chip row for display mode, not a tall radio list — keeps
        // the sheet compact.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final mode in DisplayMode.values)
                FilterChip(
                  selected: selectedMode == mode,
                  showCheckmark: false,
                  label: Text(mode.toLocale(context)),
                  onSelected: (_) => ref
                      .read(libraryDisplayModeProvider.notifier)
                      .update(mode),
                ),
            ],
          ),
        ),
        if (isGridMode) ...[
          _Heading(isLandscape
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
        ],
        _Heading(context.l10n.badges),
        CustomCheckboxListTile(
          title: context.l10n.downloaded,
          provider: downloadedBadgeProvider,
          onChanged: ref.read(downloadedBadgeProvider.notifier).update,
          tristate: false,
        ),
        CustomCheckboxListTile(
          title: context.l10n.unread,
          provider: unreadBadgeProvider,
          onChanged: ref.read(unreadBadgeProvider.notifier).update,
          tristate: false,
        ),
        CustomCheckboxListTile(
          title: context.l10n.continueReadingButton,
          provider: showContinueReadingButtonProvider,
          onChanged:
              ref.read(showContinueReadingButtonProvider.notifier).update,
          tristate: false,
        ),
        CustomCheckboxListTile(
          title: context.l10n.languageBadge,
          provider: languageBadgeProvider,
          onChanged: ref.read(languageBadgeProvider.notifier).update,
          tristate: false,
        ),
        if (ref.watch(languageBadgeProvider).ifNull(false))
          CustomCheckboxListTile(
            title: context.l10n.useLangIcon,
            provider: useLangIconProvider,
            onChanged: ref.read(useLangIconProvider.notifier).update,
            tristate: false,
          ),
        CustomCheckboxListTile(
          title: context.l10n.localBadge,
          provider: localBadgeProvider,
          onChanged: ref.read(localBadgeProvider.notifier).update,
          tristate: false,
        ),
        CustomCheckboxListTile(
          title: context.l10n.sourceBadge,
          provider: sourceBadgeProvider,
          onChanged: ref.read(sourceBadgeProvider.notifier).update,
          tristate: false,
        ),
        _Heading(context.l10n.tabs),
        CustomCheckboxListTile(
          title: context.l10n.categoryTabs,
          provider: categoryTabsProvider,
          onChanged: ref.read(categoryTabsProvider.notifier).update,
          tristate: false,
        ),
        CustomCheckboxListTile(
          title: context.l10n.showHiddenCategories,
          provider: showHiddenCategoriesProvider,
          onChanged: ref.read(showHiddenCategoriesProvider.notifier).update,
          tristate: false,
        ),
        CustomCheckboxListTile(
          title: context.l10n.categoryNumberOfItems,
          provider: categoryNumberOfItemsProvider,
          onChanged: ref.read(categoryNumberOfItemsProvider.notifier).update,
          tristate: false,
        ),
      ],
    );
  }
}

/// Compact section header (24dp/tight padding, primary-tinted label),
/// consistent with the filter tab's "Tracked" heading.
class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Text(
        text,
        style: context.theme.textTheme.labelLarge?.copyWith(
          color: context.theme.colorScheme.primary,
        ),
      ),
    );
  }
}
