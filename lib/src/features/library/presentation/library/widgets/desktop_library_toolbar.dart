// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

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
///
/// When the row is too narrow to leave the search field a usable width, the
/// toolbar switches to compact mode: Sort and Filter drop their text labels
/// and become icon buttons (see [_toolbarIsCompact]). Full mode renders
/// exactly the labelled layout.
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = _toolbarIsCompact(
            context,
            constraints,
            trailingCount: trailing.length,
          );
          final searchField = DesktopSearchField(
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
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.help_outline_rounded),
                tooltip: context.l10n.searchTips,
                onPressed: () => showSearchTips(context),
              ),
            ],
          );
          final filterBox = DesktopToolbarBox(
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
                    if (!compact) Text(context.l10n.filter),
                    const Icon(Icons.arrow_drop_down_rounded, size: 22),
                  ],
                ),
              ),
            ),
          );
          final displayBox = DesktopToolbarBox(
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
          );
          // Compact Filter drops the text but keeps its tooltip, so the
          // button stays discoverable.
          final controls = [
            _DesktopSortControl(compact: compact),
            if (compact)
              Tooltip(message: context.l10n.filter, child: filterBox)
            else
              filterBox,
            displayBox,
            ...trailing,
          ];
          if (compact) {
            // Everything besides the search field has a fixed width, so the
            // field takes the rest, floored at 160 px. When that does not
            // fit, the row lays out past the viewport inside an OverflowBox
            // (which never reports a flex overflow) and the excess clips.
            final gaps = (3 + trailing.length) * 10.0;
            final fixedBesidesSearch =
                _sortCompactWidth +
                _filterCompactWidth +
                _displayBoxWidth +
                gaps +
                trailing.length * 40.0;
            final contentWidth = constraints.maxWidth - 24.0;
            final searchWidth = math.max(
              160.0,
              contentWidth - fixedBesidesSearch,
            );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRect(
                child: OverflowBox(
                  maxWidth: double.infinity,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    spacing: 10,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: searchWidth, child: searchField),
                      ...controls,
                    ],
                  ),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: searchField),
                ...controls,
              ],
            ),
          );
        },
      ),
    );
  }
}

/// True when the toolbar is too narrow to keep the labelled layout: the
/// space the full layout leaves for the search box would drop below a usable
/// width. The Filter box is measured with a [TextPainter] under the current
/// text style and [MediaQuery.textScalerOf], so larger text flips the switch
/// sooner; the usable search width itself scales the same way, since it is a
/// text width too.
// Fixed chrome of the toolbar boxes, shared by the compact-mode switch and
// the compact layout so the two agree on what fits.
const _sortFullWidth = 230.0;
// Filter box around its label: left/right padding, the 18 px icon and 22 px
// caret with an 8 px gap on each side of the text.
const _filterFullChrome = 12.0 + 6.0 + 18.0 + 8.0 + 8.0 + 22.0;
// Compact Filter: same padding, icon and caret, one gap, no label.
const _filterCompactWidth = 12.0 + 6.0 + 18.0 + 8.0 + 22.0;
// Display box: padding, the 20 px icon and 22 px caret, 2 px apart.
const _displayBoxWidth = 10.0 + 6.0 + 20.0 + 2.0 + 22.0;
// Compact Sort: 48 px trigger, 1 px divider, 40 px direction button.
const _sortCompactWidth = 48.0 + 1.0 + 40.0;

bool _toolbarIsCompact(
  BuildContext context,
  BoxConstraints constraints, {
  required int trailingCount,
}) {
  if (!constraints.hasBoundedWidth) return false;
  final scaler = MediaQuery.textScalerOf(context);
  final label = TextPainter(
    text: TextSpan(
      text: context.l10n.filter,
      style: DefaultTextStyle.of(context).style,
    ),
    textDirection: Directionality.of(context),
    textScaler: scaler,
  )..layout();
  final labelWidth = label.width;
  label.dispose();
  final gaps = (3 + trailingCount) * 10.0;
  final neededBesidesSearch =
      24.0 +
      gaps +
      _sortFullWidth +
      _filterFullChrome +
      labelWidth +
      _displayBoxWidth +
      trailingCount * 40.0;
  return constraints.maxWidth - neededBesidesSearch < scaler.scale(280.0);
}

/// Sort field menu + direction toggle in one 230 px box: the menu trigger
/// fills the remaining width and a 40 px direction button sits past a 1 px
/// divider. Lists the same sorts in the same order as the organizer
/// ([librarySortDisplayOrder]), hiding Tracker score unless a tracker is
/// logged in. Picking the already-active Random re-rolls the order via
/// [librarySortRandomSeedProvider], mirroring [LibraryMangaSortTile]. The
/// direction button is disabled for Random, whose comparator ignores
/// direction by design.
///
/// In compact mode the trigger shrinks to a 48 px icon button (the caret is
/// dropped) carrying the current sort's label as its tooltip; the menu, the
/// divider and the direction button are unchanged.
class _DesktopSortControl extends ConsumerWidget {
  const _DesktopSortControl({this.compact = false});

  final bool compact;

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
    final menuChildren = [
      for (final sort in sorts)
        MenuItemButton(
          leadingIcon: sort == current
              ? const Icon(Icons.check_rounded, size: 18)
              : null,
          onPressed: () {
            if (sort == MangaSort.random && sort == current) {
              final seed = ref.read(librarySortRandomSeedProvider) ?? 0;
              ref.read(librarySortRandomSeedProvider.notifier).update(seed + 1);
            } else {
              ref.read(libraryMangaSortProvider.notifier).update(sort);
            }
          },
          child: Text(sort.toLocale(context)),
        ),
    ];
    final directionButton = SizedBox(
      width: 40,
      child: IconButton(
        iconSize: 20,
        color: scheme.onSurface,
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
    if (compact) {
      return DesktopToolbarBox(
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: MenuAnchor(
                style: const MenuStyle(
                  minimumSize: WidgetStatePropertyAll(Size(230, 0)),
                ),
                menuChildren: menuChildren,
                builder: (context, menu, _) => Tooltip(
                  message: current.toLocale(context),
                  child: InkWell(
                    onTap: () => menu.isOpen ? menu.close() : menu.open(),
                    child: Center(
                      child: Icon(
                        Icons.sort_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(width: 1, height: 22, color: scheme.outlineVariant),
            directionButton,
          ],
        ),
      );
    }
    return DesktopToolbarBox(
      width: 230,
      child: Row(
        children: [
          Expanded(
            child: MenuAnchor(
              style: const MenuStyle(
                minimumSize: WidgetStatePropertyAll(Size(230, 0)),
              ),
              menuChildren: menuChildren,
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
          directionButton,
        ],
      ),
    );
  }
}
