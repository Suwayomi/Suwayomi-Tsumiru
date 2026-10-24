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
import '../../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../../../tracking/data/tracker_repository.dart';
import '../controller/library_controller.dart';
import 'desktop_library_panels.dart';
import 'library_filter_content.dart';
import 'library_manga_organizer.dart';

class DesktopToolbarBox extends StatefulWidget {
  const DesktopToolbarBox({
    super.key,
    this.width,
    this.borderColor,
    required this.child,
  });

  final double? width;

  /// Overrides the border color, e.g. while a filter is active.
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

/// Keeps search mounted as Sort/Filter switch to icons when the labelled layout cannot fit.
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
            // Dropdown navigation clears the query; opening a series from the grid keeps it.
            onNavigate: () =>
                ref.read(libraryQueryProvider.notifier).update(''),
            // Grid results already appear below; the dropdown only needs Go to and Search all sources.
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
          // Keep search in the same Expanded slot across modes to preserve focus, selection and dropdown.
          final row = Row(
            spacing: 10,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: searchField),
              _DesktopSortControl(compact: compact),
              if (compact)
                Tooltip(message: context.l10n.filter, child: filterBox)
              else
                filterBox,
              displayBox,
              ...trailing,
            ],
          );
          if (!compact || !constraints.hasBoundedWidth) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: row,
            );
          }
          // Retain the same row and zero-width search state inside a scroller when fixed controls cannot fit.
          final minWidth = _compactFixedWidth(trailing.length);
          if (constraints.maxWidth >= minWidth) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: row,
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minWidth - 24.0, child: row),
            ),
          );
        },
      ),
    );
  }
}

// Shared toolbar widths keep the compact breakpoint and layout calculations consistent.
const _sortFullWidth = 230.0;
// Horizontal padding, 18 px icon, 22 px caret, and two 8 px gaps.
const _filterFullChrome = 12.0 + 6.0 + 18.0 + 8.0 + 8.0 + 22.0;
// Same chrome as Filter with one gap and no label.
const _filterCompactWidth = 12.0 + 6.0 + 18.0 + 8.0 + 22.0;
// Horizontal padding, 20 px icon, 22 px caret, and 2 px gap.
const _displayBoxWidth = 10.0 + 6.0 + 20.0 + 2.0 + 22.0;
// 48 px trigger, 1 px divider, 40 px direction button.
const _sortCompactWidth = 48.0 + 1.0 + 40.0;
// Content-width boxes need 2 px for borders; the full Sort width already includes them.
const _boxBorderWidth = 2.0;
// Trailing actions reserve the default 48 px IconButton/PopupMenuButton width.
const _trailingButtonWidth = 48.0;

/// Fixed controls' minimum width; below it the zero-width search stays mounted while the row scrolls.
double _compactFixedWidth(int trailingCount) =>
    24.0 +
    (3 + trailingCount) * 10.0 +
    (_sortCompactWidth + _boxBorderWidth) +
    (_filterCompactWidth + _boxBorderWidth) +
    (_displayBoxWidth + _boxBorderWidth) +
    trailingCount * _trailingButtonWidth;

/// Minimum compact toolbar width including a usable search field.
double libraryTopBarSlotMinWidth(int trailingCount) =>
    _compactFixedWidth(trailingCount) + kTopBarSearchMinWidth;

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
      _boxBorderWidth +
      _displayBoxWidth +
      _boxBorderWidth +
      trailingCount * _trailingButtonWidth;
  return constraints.maxWidth - neededBesidesSearch < scaler.scale(280.0);
}

// Random re-rolls on selection and ignores direction; compact mode must preserve those controls.
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
