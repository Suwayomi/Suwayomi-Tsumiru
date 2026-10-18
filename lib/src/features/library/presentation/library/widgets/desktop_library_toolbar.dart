// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../routes/navigation.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/search_field.dart';
import '../../../../tracking/data/tracker_repository.dart';
import '../controller/library_controller.dart';
import 'desktop_library_panels.dart';
import 'library_filter_content.dart';
import 'library_manga_organizer.dart';

/// Desktop Library toolbar chrome, copied from Tsumige's `ToolbarBox`
/// (`vn-launcher/.../library/widgets/library_toolbar.dart`, lines ~234-262):
/// a 40 px box, 10 px radius, `surfaceContainer` fill and an `outlineVariant`
/// border that brightens on hover. Not imported from that repo.
class DesktopToolbarBox extends StatefulWidget {
  const DesktopToolbarBox({
    super.key,
    this.width,
    this.borderColor,
    required this.child,
  });

  final double? width;

  /// Overrides the border color (the Filter box uses `primary` while any
  /// filter is active).
  final Color? borderColor;
  final Widget child;

  @override
  State<DesktopToolbarBox> createState() => _DesktopToolbarBoxState();
}

class _DesktopToolbarBoxState extends State<DesktopToolbarBox> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: widget.width,
        height: 40,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                widget.borderColor ??
                (_hovered
                    ? scheme.onSurface.withValues(alpha: 0.18)
                    : scheme.outlineVariant),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Shows the library search DSL cheat-sheet (opened from the search bar's help
/// icon), so the query syntax is discoverable rather than hidden.
void showSearchTips(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.searchTips),
      // The `{a|b}` OR-group example lives here rather than in the l10n string
      // because ICU message syntax reserves curly braces for placeholders.
      content: Text(
        '${context.l10n.searchTipsBody}'
        '\nMatch any of these: {genre:action|genre:romance}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    ),
    animationStyle: context.motionStyle,
  );
}

/// The desktop Library toolbar: one 64 px row (12 px horizontal padding,
/// 40 px controls, 10 px gaps) with an always-visible search field, a sort
/// control with a separate direction button, Filter and Display buttons that
/// open anchored dropdown panels, and whatever [trailing] controls the
/// variant keeps reachable (sync, update menu, migration picker). No title.
/// Phone and tablet never see this.
class DesktopLibraryToolbar extends HookConsumerWidget {
  const DesktopLibraryToolbar({super.key, this.trailing = const []});

  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final filterButtonKey = useMemoized(GlobalKey.new);
    final displayButtonKey = useMemoized(GlobalKey.new);
    final filterFocus = useMemoized(FocusNode.new);
    final displayFocus = useMemoized(FocusNode.new);
    useEffect(() {
      return () {
        filterFocus.dispose();
        displayFocus.dispose();
      };
    }, [filterFocus, displayFocus]);
    final activeFilters = watchLibraryFilterActiveCount(ref);
    Widget filterIcon = const Icon(Icons.filter_list_rounded, size: 18);
    if (activeFilters > 0) {
      filterIcon = Badge.count(
        count: activeFilters,
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
        child: filterIcon,
      );
    }
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          spacing: 10,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: DesktopToolbarBox(child: _DesktopSearchField()),
            ),
            const _DesktopSortControl(),
            const _DesktopSortDirectionButton(),
            DesktopToolbarBox(
              key: filterButtonKey,
              borderColor: activeFilters > 0 ? scheme.primary : null,
              child: InkWell(
                focusNode: filterFocus,
                onTap: () => showLibraryFilterPanel(
                  context: context,
                  buttonKey: filterButtonKey,
                  focusNode: filterFocus,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 6),
                  child: Row(
                    spacing: 8,
                    children: [
                      filterIcon,
                      Text(context.l10n.filter),
                      const Icon(Icons.arrow_drop_down_rounded, size: 22),
                    ],
                  ),
                ),
              ),
            ),
            DesktopToolbarBox(
              key: displayButtonKey,
              child: Tooltip(
                message: context.l10n.display,
                child: InkWell(
                  focusNode: displayFocus,
                  onTap: () => showLibraryDisplayPanel(
                    context: context,
                    buttonKey: displayButtonKey,
                    focusNode: displayFocus,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 10, right: 6),
                    child: Row(
                      spacing: 2,
                      children: [
                        Icon(Icons.grid_view_rounded, size: 20),
                        Icon(Icons.arrow_drop_down_rounded, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }
}

/// The toolbar search field. Same behaviour as today's library search: writes
/// [libraryQueryProvider] on change, initial text from it, a clear button,
/// and the Search tips + search-all-sources actions. Always visible and never
/// autofocused on desktop.
class _DesktopSearchField extends HookConsumerWidget {
  const _DesktopSearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(libraryQueryProvider) ?? '';
    final controller = useMemoized(() => DslSearchController(text: query));
    useEffect(() => controller.dispose, [controller]);
    // A query set programmatically (tapping a tag opens the library on that
    // tag) refreshes the field; while typing both sides already agree.
    ref.listen<String?>(libraryQueryProvider, (_, next) {
      final value = next ?? '';
      if (controller.text != value) controller.text = value;
    });

    const iconConstraints = BoxConstraints(minWidth: 36, minHeight: 36);
    return TextField(
      controller: controller,
      autofocus: false,
      onChanged: (val) => ref.read(libraryQueryProvider.notifier).update(val),
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        hintText: context.l10n.searchLibraryHint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        prefixIconConstraints: iconConstraints,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              iconSize: 20,
              padding: const EdgeInsets.all(8),
              constraints: iconConstraints,
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: context.l10n.searchTips,
              onPressed: () => showSearchTips(context),
            ),
            IconButton(
              iconSize: 20,
              padding: const EdgeInsets.all(8),
              constraints: iconConstraints,
              icon: const Icon(Icons.travel_explore_rounded),
              tooltip: context.l10n.globalSearch,
              onPressed: query.isNotBlank
                  ? () => openGlobalSearch(
                      context,
                      query: ref.read(libraryQueryProvider),
                    )
                  : null,
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                iconSize: 20,
                padding: const EdgeInsets.all(8),
                constraints: iconConstraints,
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  controller.clear();
                  ref.read(libraryQueryProvider.notifier).update('');
                },
              ),
          ],
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: 40),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}

/// Sort field menu, 180 px wide. Lists the same sorts in the same order as
/// the organizer ([librarySortDisplayOrder]), hiding Tracker score unless a
/// tracker is logged in. Picking the already-active Random re-rolls the order
/// via [librarySortRandomSeedProvider], mirroring [LibraryMangaSortTile].
class _DesktopSortControl extends ConsumerWidget {
  const _DesktopSortControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(libraryMangaSortProvider) ?? DBKeys.mangaSort.initial;
    final hasTrackers =
        ref.watch(loggedInTrackersProvider).value?.isNotEmpty ?? false;
    final sorts = [
      for (final sort in librarySortDisplayOrder)
        if (sort != MangaSort.trackerScore || hasTrackers) sort,
    ];
    return DesktopToolbarBox(
      width: 180,
      child: MenuAnchor(
        style: const MenuStyle(
          minimumSize: WidgetStatePropertyAll(Size(180, 0)),
        ),
        menuChildren: [
          for (final sort in sorts)
            MenuItemButton(
              leadingIcon: sort == current
                  ? const Icon(Icons.check_rounded, size: 18)
                  : null,
              onPressed: () {
                if (sort == MangaSort.random && sort == current) {
                  final seed = ref.read(librarySortRandomSeedProvider) ?? 0;
                  ref
                      .read(librarySortRandomSeedProvider.notifier)
                      .update(seed + 1);
                } else {
                  ref.read(libraryMangaSortProvider.notifier).update(sort);
                }
              },
              child: Text(sort.toLocale(context)),
            ),
        ],
        builder: (context, menu, _) => InkWell(
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current.toLocale(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down_rounded, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Separate square direction button. Disabled for Random, whose comparator
/// ignores direction by design.
class _DesktopSortDirectionButton extends ConsumerWidget {
  const _DesktopSortDirectionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ascending = ref.watch(libraryMangaSortDirectionProvider).ifNull(true);
    final isRandom =
        (ref.watch(libraryMangaSortProvider) ?? DBKeys.mangaSort.initial) ==
        MangaSort.random;
    return DesktopToolbarBox(
      width: 40,
      child: IconButton(
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(
          ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
        ),
        onPressed: isRandom
            ? null
            : () => ref
                  .read(libraryMangaSortDirectionProvider.notifier)
                  .update(!ascending),
      ),
    );
  }
}
