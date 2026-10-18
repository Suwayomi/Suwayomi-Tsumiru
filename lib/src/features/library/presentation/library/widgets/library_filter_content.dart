// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../tracking/data/tracker_repository.dart';
import '../../category/controller/edit_category_controller.dart';
import '../controller/library_controller.dart';
import '../controller/library_manga_list.dart';
import 'library_filter_segments.dart';

/// Full segmented filter content, shared by the desktop filter panel
/// (two columns) and the organizer Filter tab (single column).
class LibraryFilterContent extends ConsumerWidget {
  const LibraryFilterContent({super.key, this.twoColumns = false});

  final bool twoColumns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const right = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LibraryRatingFilter(),
        LibraryTrackerSegments(),
        LibraryCategoryFilter(),
        LibraryTagFilter(),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const LibraryFilterHeader(),
        // Two columns need a bounded height (the desktop panel): the left
        // column scrolls internally, so a radio fallback for long labels
        // never overflows the panel. The right column's tag list grows to
        // fill the remaining height and scrolls inside itself, so both
        // column bottoms align. With many trackers the tag list shrinks
        // first (down to ~3 rows); only if the right column still doesn't
        // fit does the right column scroll as one. The left column is
        // unaffected either way.
        if (twoColumns)
          const Expanded(
            child: Row(
              // Stretch both columns to the full row height: the left
              // column scrolls inside that height and the right column's
              // tag list expands into it, aligning both bottoms.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(child: LibraryFilterSegments()),
                ),
                SizedBox(width: 24),
                Expanded(child: _FilterRightColumn()),
              ],
            ),
          )
        else ...[
          const LibraryFilterSegments(),
          right,
        ],
      ],
    );
  }
}

/// Slots of the two-column filter panel's right column.
enum _FilterRightSlot { fixed, tags }

/// Lays out the right column without intrinsic measurements (a [ListView]
/// cannot answer those): the fixed filters get their natural height and the
/// tag list takes the leftover viewport height, shrinking to
/// [_minTagListHeight] first. Anything beyond the viewport paints past the
/// layout size, where the surrounding scroll view picks it up — so the right
/// column scrolls as one only when the fixed filters plus that minimum
/// exceed the row height.
class _FilterRightDelegate extends MultiChildLayoutDelegate {
  _FilterRightDelegate({required this.viewportHeight});

  final double viewportHeight;

  @override
  Size getSize(BoxConstraints constraints) =>
      Size(constraints.maxWidth, viewportHeight);

  @override
  void performLayout(Size size) {
    final fixed = layoutChild(
      _FilterRightSlot.fixed,
      BoxConstraints(maxWidth: size.width),
    );
    positionChild(_FilterRightSlot.fixed, Offset.zero);
    final listHeight = math.max(_minTagListHeight, size.height - fixed.height);
    layoutChild(
      _FilterRightSlot.tags,
      BoxConstraints.tightFor(width: size.width, height: listHeight),
    );
    positionChild(_FilterRightSlot.tags, Offset(0, fixed.height));
  }

  @override
  bool shouldRelayout(_FilterRightDelegate oldDelegate) =>
      oldDelegate.viewportHeight != viewportHeight;
}

/// Right column of the two-column filter panel: rating, per-tracker rows,
/// categories, tag search, then the tag list expanding into the leftover
/// height and scrolling inside itself. The left column is unaffected.
class _FilterRightColumn extends HookConsumerWidget {
  const _FilterRightColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    final data = _readTagFilterData(ref, query.value);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        if (!viewportHeight.isFinite) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const LibraryRatingFilter(),
                const LibraryTrackerSegments(),
                const LibraryCategoryFilter(),
                _TagSearchHeader(
                  onQueryChanged: (value) => query.value = value,
                ),
                _TagListView(data: data, shrinkWrap: true),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          child: CustomMultiChildLayout(
            delegate: _FilterRightDelegate(viewportHeight: viewportHeight),
            children: [
              LayoutId(
                id: _FilterRightSlot.fixed,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LibraryRatingFilter(),
                    const LibraryTrackerSegments(),
                    const LibraryCategoryFilter(),
                    _TagSearchHeader(
                      onQueryChanged: (value) => query.value = value,
                    ),
                  ],
                ),
              ),
              LayoutId(
                id: _FilterRightSlot.tags,
                child: _TagListView(data: data),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Filter" title plus a Reset text button. Reset clears every library filter
/// (tri-states, rating, categories, tags, per-tracker filters) and is
/// disabled while nothing is active.
class LibraryFilterHeader extends ConsumerWidget {
  const LibraryFilterHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = watchLibraryFilterActiveCount(ref);
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.filter,
            style: context.theme.textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: active > 0 ? () => resetLibraryFilters(ref) : null,
          child: Text(context.l10n.reset),
        ),
      ],
    );
  }
}

/// The seven tri-state filters with short headings: Downloaded (Any/Yes/No),
/// Storage (Any/On Device/Remote), Read Status (Any/Unread/Read), Started,
/// Bookmarked, Completed and Lewd (Any/Yes/No).
///
/// Any=null, first option=true, second option=false on the existing
/// providers, exactly as `TriStateFilterTile` maps them.
class LibraryFilterSegments extends ConsumerWidget {
  const LibraryFilterSegments({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LibraryTriStateSegment(
          heading: context.l10n.filterShortDownloaded,
          provider: libraryMangaFilterDownloadedProvider,
          onChanged: ref
              .read(libraryMangaFilterDownloadedProvider.notifier)
              .update,
        ),
        LibraryTriStateSegment(
          heading: context.l10n.filterHeaderStorage,
          provider: libraryMangaFilterOfflineProvider,
          onChanged: ref
              .read(libraryMangaFilterOfflineProvider.notifier)
              .update,
          includedLabel: context.l10n.filterOptionOnDevice,
          excludedLabel: context.l10n.filterOptionRemote,
        ),
        LibraryTriStateSegment(
          heading: context.l10n.filterHeaderReadStatus,
          provider: libraryMangaFilterUnreadProvider,
          onChanged: ref.read(libraryMangaFilterUnreadProvider.notifier).update,
          includedLabel: context.l10n.filterOptionUnread,
          excludedLabel: context.l10n.filterOptionRead,
        ),
        LibraryTriStateSegment(
          heading: context.l10n.filterShortStarted,
          provider: libraryMangaFilterStartedProvider,
          onChanged: ref
              .read(libraryMangaFilterStartedProvider.notifier)
              .update,
        ),
        LibraryTriStateSegment(
          heading: context.l10n.filterShortBookmarked,
          provider: libraryMangaFilterBookmarkedProvider,
          onChanged: ref
              .read(libraryMangaFilterBookmarkedProvider.notifier)
              .update,
        ),
        LibraryTriStateSegment(
          heading: context.l10n.filterShortCompleted,
          provider: libraryMangaFilterCompletedProvider,
          onChanged: ref
              .read(libraryMangaFilterCompletedProvider.notifier)
              .update,
        ),
        LibraryTriStateSegment(
          heading: context.l10n.filterShortLewd,
          provider: libraryMangaFilterLewdProvider,
          onChanged: ref.read(libraryMangaFilterLewdProvider.notifier).update,
        ),
      ],
    );
  }
}

/// Number of active library filters: one per non-null tri-state, the rating
/// threshold, enabled category/tag filters and per-tracker filters.
int watchLibraryFilterActiveCount(WidgetRef ref) {
  var count = 0;
  for (final provider in [
    libraryMangaFilterDownloadedProvider,
    libraryMangaFilterOfflineProvider,
    libraryMangaFilterUnreadProvider,
    libraryMangaFilterStartedProvider,
    libraryMangaFilterBookmarkedProvider,
    libraryMangaFilterCompletedProvider,
    libraryMangaFilterLewdProvider,
  ]) {
    if (ref.watch(provider) != null) count++;
  }
  if ((ref.watch(libraryMangaFilterMinRatingProvider) ?? 0) > 0) count++;
  if (ref.watch(libraryFilterCategoriesProvider).ifNull(false)) count++;
  if (ref.watch(libraryFilterTagsProvider).ifNull(false)) count++;
  for (final value in ref.watch(libraryTrackerFiltersProvider).values) {
    if (value != null) count++;
  }
  return count;
}

/// Clears every library filter back to its inactive value.
void resetLibraryFilters(WidgetRef ref) {
  ref.read(libraryMangaFilterDownloadedProvider.notifier).update(null);
  ref.read(libraryMangaFilterOfflineProvider.notifier).update(null);
  ref.read(libraryMangaFilterUnreadProvider.notifier).update(null);
  ref.read(libraryMangaFilterStartedProvider.notifier).update(null);
  ref.read(libraryMangaFilterBookmarkedProvider.notifier).update(null);
  ref.read(libraryMangaFilterCompletedProvider.notifier).update(null);
  ref.read(libraryMangaFilterLewdProvider.notifier).update(null);
  ref.read(libraryMangaFilterMinRatingProvider.notifier).update(0);
  ref.read(libraryFilterCategoriesProvider.notifier).update(false);
  ref.read(libraryFilterCategoriesIncludeProvider.notifier).update(const []);
  ref.read(libraryFilterCategoriesExcludeProvider.notifier).update(const []);
  ref.read(libraryFilterTagsProvider.notifier).update(false);
  ref.read(libraryFilterTagsIncludeProvider.notifier).update(const []);
  ref.read(libraryFilterTagsExcludeProvider.notifier).update(const []);
  final trackers = ref.read(loggedInTrackersProvider).value ?? const [];
  for (final tracker in trackers) {
    ref
        .read(libraryMangaFilterTrackerProvider(trackerId: tracker.id).notifier)
        .update(null);
  }
}

/// Minimum personal star rating. Tapping star N sets the threshold to N;
/// tapping the current threshold clears it (show all).
class LibraryRatingFilter extends ConsumerWidget {
  const LibraryRatingFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final min = ref.watch(libraryMangaFilterMinRatingProvider) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(context.l10n.minimumRating),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int star = 1; star <= 5; star++)
              InkResponse(
                radius: 18,
                onTap: () => ref
                    .read(libraryMangaFilterMinRatingProvider.notifier)
                    .update(min == star ? 0 : star),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    star <= min
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 22,
                    color: star <= min
                        ? brandStarColor(context.theme.brightness)
                        : context.theme.unselectedWidgetColor,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One Any / Yes / No row per logged-in tracker. Hidden when no tracker is
/// logged in.
class LibraryTrackerSegments extends ConsumerWidget {
  const LibraryTrackerSegments({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(loggedInTrackersProvider).value ?? const [];
    if (loggedIn.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(context.l10n.filterTracked),
        for (final tracker in loggedIn)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tracker.name,
                    style: context.theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 200,
                  child: _TrackerSegments(trackerId: tracker.id),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrackerSegments extends ConsumerWidget {
  const _TrackerSegments({required this.trackerId});

  final int trackerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdaptiveSegments<bool?>(
      value: ref.watch(libraryMangaFilterTrackerProvider(trackerId: trackerId)),
      onChanged: (next) => ref
          .read(
            libraryMangaFilterTrackerProvider(trackerId: trackerId).notifier,
          )
          .update(next),
      options: [
        SegmentOption(value: null, label: context.l10n.filterStateAny),
        SegmentOption(value: true, label: context.l10n.yes),
        SegmentOption(value: false, label: context.l10n.no),
      ],
    );
  }
}

/// Category include/exclude summary ("Any category" when nothing is picked)
/// with an Edit button opening the include/exclude dialog. Tapping the row
/// toggles category filtering.
class LibraryCategoryFilter extends ConsumerWidget {
  const LibraryCategoryFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(libraryFilterCategoriesProvider).ifNull(false);
    final include =
        (ref.watch(libraryFilterCategoriesIncludeProvider) ?? const <String>[])
            .toSet();
    final exclude =
        (ref.watch(libraryFilterCategoriesExcludeProvider) ?? const <String>[])
            .toSet();
    final categories = ref.watch(visibleCategoryListProvider).value ?? const [];
    String nameFor(String id) =>
        categories
            .where((c) => c.id.toString() == id)
            .map((c) => c.name)
            .firstOrNull ??
        id;
    final summary = include.isEmpty && exclude.isEmpty
        ? context.l10n.anyCategory
        : [
            for (final id in include) '+${nameFor(id)}',
            for (final id in exclude) '−${nameFor(id)}',
          ].join(', ');
    final scheme = context.theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(context.l10n.categories),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => ref
              .read(libraryFilterCategoriesProvider.notifier)
              .update(!enabled),
          child: Container(
            padding: const EdgeInsets.only(
              left: 12,
              top: 4,
              bottom: 4,
              right: 4,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.textTheme.bodyMedium?.copyWith(
                      color: include.isEmpty && exclude.isEmpty
                          ? scheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const CategoryFilterDialog(),
                    animationStyle: context.motionStyle,
                  ),
                  child: Text(context.l10n.edit),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Minimum height of the expanded tag list: ~3 tag rows (each ~36 px: 8 px
/// padding above and below a ~20 px line). The list shrinks to this before
/// the right column starts scrolling as a whole.
const _minTagListHeight = 112.0;

/// Next tag state when tapping: include → exclude → ignored.
bool? _nextTagValue(bool? current) {
  if (current == null) return true;
  if (current == true) return false;
  return null;
}

/// Tag rows shared by the single-column filter and the two-column panel's
/// right column: the filtered tags with series counts plus their
/// include/exclude state and the callbacks that change it.
class _TagFilterData {
  const _TagFilterData({
    required this.isLoading,
    required this.tags,
    required this.counts,
    required this.hasCounts,
    required this.hasSelection,
    required this.stateFor,
    required this.toggle,
    required this.clear,
  });

  final bool isLoading;
  final List<String> tags;
  final Map<String, int> counts;
  final bool hasCounts;
  final bool hasSelection;
  final bool? Function(String tag) stateFor;
  final void Function(String tag) toggle;
  final VoidCallback clear;
}

/// Reads the tag filter rows for [rawQuery] (untrimmed search field text).
_TagFilterData _readTagFilterData(WidgetRef ref, String rawQuery) {
  final tagsAsync = ref.watch(libraryTagListProvider);
  final includeSet =
      (ref.watch(libraryFilterTagsIncludeProvider) ?? const <String>[]).toSet();
  final excludeSet =
      (ref.watch(libraryFilterTagsExcludeProvider) ?? const <String>[]).toSet();
  final mangaList = ref.watch(libraryMangaListProvider).value;

  bool? stateFor(String tag) {
    if (excludeSet.contains(tag)) return false;
    if (includeSet.contains(tag)) return true;
    return null;
  }

  void toggle(String tag) {
    final next = _nextTagValue(stateFor(tag));
    final newInclude = Set<String>.from(includeSet)..remove(tag);
    final newExclude = Set<String>.from(excludeSet)..remove(tag);
    if (next == true) newInclude.add(tag);
    if (next == false) newExclude.add(tag);
    ref
        .read(libraryFilterTagsIncludeProvider.notifier)
        .update(newInclude.toList());
    ref
        .read(libraryFilterTagsExcludeProvider.notifier)
        .update(newExclude.toList());
    ref
        .read(libraryFilterTagsProvider.notifier)
        .update(newInclude.isNotEmpty || newExclude.isNotEmpty);
  }

  void clear() {
    ref.read(libraryFilterTagsIncludeProvider.notifier).update(const []);
    ref.read(libraryFilterTagsExcludeProvider.notifier).update(const []);
    ref.read(libraryFilterTagsProvider.notifier).update(false);
  }

  final counts = <String, int>{};
  if (mangaList != null) {
    for (final manga in mangaList) {
      final tags = {
        for (final genre in manga.genre) genre.toLowerCase(),
        for (final tag in (manga.metaData.userTags ?? const <String>[]))
          tag.toLowerCase(),
      };
      for (final tag in tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
  }

  final allTags = tagsAsync.value ?? const <String>[];
  final q = rawQuery.trim().toLowerCase();
  final tags = q.isEmpty
      ? allTags
      : allTags.where((t) => t.toLowerCase().contains(q)).toList();
  return _TagFilterData(
    isLoading: tagsAsync.isLoading,
    tags: tags,
    counts: counts,
    hasCounts: mangaList != null,
    hasSelection: includeSet.isNotEmpty || excludeSet.isNotEmpty,
    stateFor: stateFor,
    toggle: toggle,
    clear: clear,
  );
}

/// One tag row: the label plus its series count, checkmarked or blocked when
/// included or excluded. "All tags" clears the selection.
Widget _tagRow(
  BuildContext context, {
  required String label,
  required bool? state,
  required VoidCallback onTap,
  int? count,
}) {
  final scheme = context.theme.colorScheme;
  final Widget? leading;
  if (state == true) {
    leading = Icon(Icons.check_rounded, size: 18, color: scheme.primary);
  } else if (state == false) {
    leading = Icon(Icons.block_rounded, size: 18, color: scheme.error);
  } else {
    leading = null;
  }
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 12)],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.textTheme.bodyMedium?.copyWith(
                color: state == null ? null : scheme.primary,
                fontWeight: state == null ? null : FontWeight.w600,
              ),
            ),
          ),
          if (count != null)
            Text(
              '$count',
              style: context.theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    ),
  );
}

/// Tag search heading plus search field, shared by both filter layouts.
class _TagSearchHeader extends StatelessWidget {
  const _TagSearchHeader({required this.onQueryChanged});

  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(context.l10n.tags),
        TextField(
          onChanged: onQueryChanged,
          style: context.theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: context.l10n.searchTags,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ],
    );
  }
}

/// The tag rows as a list, scrolling inside whatever height its parent gives
/// it (or shrink-wrapped inside a scrollable parent).
class _TagListView extends StatelessWidget {
  const _TagListView({required this.data, this.shrinkWrap = false});

  final _TagFilterData data;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    if (data.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return ListView(
      shrinkWrap: shrinkWrap,
      children: [
        _tagRow(
          context,
          label: context.l10n.allTags,
          state: data.hasSelection ? null : true,
          onTap: data.clear,
        ),
        for (final tag in data.tags)
          _tagRow(
            context,
            label: tag,
            state: data.stateFor(tag),
            onTap: () => data.toggle(tag),
            count: data.hasCounts ? data.counts[tag.toLowerCase()] ?? 0 : null,
          ),
      ],
    );
  }
}

/// Tag filter: a search field plus the library's tags with series counts.
/// "All tags" first clears the selection; tapping a tag cycles it through
/// include → exclude → ignored, reusing the tag filter providers.
///
/// Single-column layout (organizer Filter tab): the list takes its intrinsic
/// height up to 150 px. The desktop two-column panel composes
/// [_TagSearchHeader] and [_TagListView] itself (see [_FilterRightColumn]).
class LibraryTagFilter extends HookConsumerWidget {
  const LibraryTagFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    final data = _readTagFilterData(ref, query.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TagSearchHeader(onQueryChanged: (value) => query.value = value),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150),
          child: _TagListView(data: data, shrinkWrap: true),
        ),
      ],
    );
  }
}

/// Dialog that tri-states each category: null = not filtered, true = include,
/// false = exclude. Picking any category enables category filtering.
class CategoryFilterDialog extends ConsumerWidget {
  const CategoryFilterDialog({super.key});

  static bool? _nextValue(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  Widget _leadingIcon(BuildContext context, bool? value) {
    final activeColor = context.theme.colorScheme.primary;
    final excludeColor = context.theme.colorScheme.error;
    if (value == null) {
      return Icon(
        Icons.check_box_outline_blank_rounded,
        color: context.theme.unselectedWidgetColor,
      );
    } else if (value == true) {
      return Icon(Icons.check_box_rounded, color: activeColor);
    } else {
      return Icon(Icons.disabled_by_default_rounded, color: excludeColor);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(visibleCategoryListProvider);
    final includeSet =
        (ref.watch(libraryFilterCategoriesIncludeProvider) ?? const <String>[])
            .toSet();
    final excludeSet =
        (ref.watch(libraryFilterCategoriesExcludeProvider) ?? const <String>[])
            .toSet();

    bool? stateFor(int id) {
      final s = id.toString();
      if (excludeSet.contains(s)) return false;
      if (includeSet.contains(s)) return true;
      return null;
    }

    void toggle(int id) {
      final s = id.toString();
      final next = _nextValue(stateFor(id));
      final newInclude = Set<String>.from(includeSet)..remove(s);
      final newExclude = Set<String>.from(excludeSet)..remove(s);
      if (next == true) newInclude.add(s);
      if (next == false) newExclude.add(s);
      ref
          .read(libraryFilterCategoriesIncludeProvider.notifier)
          .update(newInclude.toList());
      ref
          .read(libraryFilterCategoriesExcludeProvider.notifier)
          .update(newExclude.toList());
      if (newInclude.isNotEmpty || newExclude.isNotEmpty) {
        ref.read(libraryFilterCategoriesProvider.notifier).update(true);
      }
    }

    final categories = categoriesAsync.value ?? [];

    return AlertDialog(
      title: Text(context.l10n.categories),
      content: SizedBox(
        width: double.maxFinite,
        child: categories.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                shrinkWrap: true,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final state = stateFor(cat.id);
                  return ListTile(
                    leading: _leadingIcon(context, state),
                    title: Text(cat.name),
                    onTap: () => toggle(cat.id),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
