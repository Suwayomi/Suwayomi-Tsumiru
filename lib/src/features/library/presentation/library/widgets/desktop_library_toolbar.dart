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
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../quick_open/presentation/unified_search/desktop_search_field.dart';
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

/// Shows the library search cheat-sheet (opened from the search bar's help
/// icon), so the query syntax is discoverable rather than hidden.
Future<void> showSearchTips(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final body = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        color: scheme.onSurfaceVariant,
      );
      Text tip(String Function(Object) format, String example) {
        const sentinel = '\u{0}';
        final template = format(sentinel);
        final parts = template.split(sentinel);
        if (parts.length < 2) {
          return Text(template.replaceAll(sentinel, example), style: body);
        }
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: parts.first),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    example,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
              if (parts.length > 1) TextSpan(text: parts.last),
            ],
          ),
          style: body,
        );
      }

      final l10n = context.l10n;
      return AlertDialog(
        title: Text(l10n.searchTips),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(l10n.searchTipsPlainWords, style: body),
            tip(l10n.searchTipsField, 'author:oda'),
            tip(l10n.searchTipsExclude, '-tag:dropped'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.close),
          ),
        ],
      );
    },
    animationStyle: context.motionStyle,
  );
}

/// The desktop Library toolbar: one 64 px row (12 px horizontal padding,
/// 40 px controls, 10 px gaps) with an always-visible search field, a
/// combined sort + direction control, Filter and Display buttons that
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
            Expanded(
              child: DesktopSearchField(
                query: ref.watch(libraryQueryProvider) ?? '',
                onChanged: (val) =>
                    ref.read(libraryQueryProvider.notifier).update(val),
                // Leaving through a dropdown result (Go to, Search all
                // sources) clears the query; opening a series from the
                // filtered grid keeps it — that path never touches this.
                onNavigate: () =>
                    ref.read(libraryQueryProvider.notifier).update(''),
                // The grid below is already the filtered library: only Go to
                // matches and Search all sources belong in the dropdown.
                showLibrarySection: false,
                hintText: context.l10n.searchLibraryHint,
                suffixActions: [
                  IconButton(
                    iconSize: 20,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(Icons.help_outline_rounded),
                    tooltip: context.l10n.searchTips,
                    onPressed: () => showSearchTips(context),
                  ),
                ],
              ),
            ),
            const _DesktopSortControl(),
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

/// Sort field menu + direction toggle in one 230 px box: the menu trigger
/// fills the remaining width and a 40 px direction button sits past a 1 px
/// divider. Lists the same sorts in the same order as the organizer
/// ([librarySortDisplayOrder]), hiding Tracker score unless a tracker is
/// logged in. Picking the already-active Random re-rolls the order via
/// [librarySortRandomSeedProvider], mirroring [LibraryMangaSortTile]. The
/// direction button is disabled for Random, whose comparator ignores
/// direction by design.
class _DesktopSortControl extends ConsumerWidget {
  const _DesktopSortControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current =
        ref.watch(libraryMangaSortProvider) ?? DBKeys.mangaSort.initial;
    final hasTrackers =
        ref.watch(loggedInTrackersProvider).value?.isNotEmpty ?? false;
    final sorts = [
      for (final sort in librarySortDisplayOrder)
        if (sort != MangaSort.trackerScore || hasTrackers) sort,
    ];
    final ascending = ref.watch(libraryMangaSortDirectionProvider).ifNull(true);
    final isRandom = current == MangaSort.random;
    return DesktopToolbarBox(
      width: 230,
      child: Row(
        children: [
          Expanded(
            child: MenuAnchor(
              style: const MenuStyle(
                minimumSize: WidgetStatePropertyAll(Size(230, 0)),
              ),
              menuChildren: [
                for (final sort in sorts)
                  MenuItemButton(
                    leadingIcon: sort == current
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                    onPressed: () {
                      if (sort == MangaSort.random && sort == current) {
                        final seed =
                            ref.read(librarySortRandomSeedProvider) ?? 0;
                        ref
                            .read(librarySortRandomSeedProvider.notifier)
                            .update(seed + 1);
                      } else {
                        ref
                            .read(libraryMangaSortProvider.notifier)
                            .update(sort);
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
                    spacing: 8,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
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
          ),
          Container(width: 1, height: 22, color: scheme.outlineVariant),
          SizedBox(
            width: 40,
            child: IconButton(
              iconSize: 20,
              color: scheme.onSurface,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
              ),
              onPressed: isRandom
                  ? null
                  : () => ref
                        .read(libraryMangaSortDirectionProvider.notifier)
                        .update(!ascending),
            ),
          ),
        ],
      ),
    );
  }
}
