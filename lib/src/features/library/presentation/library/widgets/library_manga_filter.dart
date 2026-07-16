// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/custom_checkbox_list_tile.dart';
import '../../../../tracking/data/tracker_repository.dart';
import '../../category/controller/edit_category_controller.dart';
import '../controller/library_controller.dart';

class LibraryMangaFilter extends ConsumerWidget {
  const LibraryMangaFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Order: Downloaded, Unread, Started, Bookmarked, Completed, [Lewd],
    // [Categories], [Trackers]. Our extra "On device" filter sits
    // next to Downloaded since both concern on-device download state.
    return ListView(
      shrinkWrap: true,
      children: [
        CustomCheckboxListTile(
          title: context.l10n.downloaded,
          provider: libraryMangaFilterDownloadedProvider,
          onChanged:
              ref.read(libraryMangaFilterDownloadedProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.onDevice,
          provider: libraryMangaFilterOfflineProvider,
          onChanged:
              ref.read(libraryMangaFilterOfflineProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.unread,
          provider: libraryMangaFilterUnreadProvider,
          onChanged: ref.read(libraryMangaFilterUnreadProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.started,
          provider: libraryMangaFilterStartedProvider,
          onChanged:
              ref.read(libraryMangaFilterStartedProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.bookmarked,
          provider: libraryMangaFilterBookmarkedProvider,
          onChanged:
              ref.read(libraryMangaFilterBookmarkedProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.completed,
          provider: libraryMangaFilterCompletedProvider,
          onChanged:
              ref.read(libraryMangaFilterCompletedProvider.notifier).update,
        ),
        CustomCheckboxListTile(
          title: context.l10n.lewd,
          provider: libraryMangaFilterLewdProvider,
          onChanged:
              ref.read(libraryMangaFilterLewdProvider.notifier).update,
        ),
        _RatingFilterRow(),
        _CategoryFilterRow(),
        _TagFilterRow(),
        _TrackerFilterSection(),
      ],
    );
  }
}

/// Minimum personal star rating to show. Tapping star N sets the threshold to N;
/// tapping the current threshold clears it (show all).
class _RatingFilterRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final min = ref.watch(libraryMangaFilterMinRatingProvider) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.minimumRating,
              style: context.theme.textTheme.bodyMedium,
            ),
          ),
          for (int star = 1; star <= 5; star++)
            InkResponse(
              radius: 18,
              onTap: () => ref
                  .read(libraryMangaFilterMinRatingProvider.notifier)
                  .update(min == star ? 0 : star),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  star <= min ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 22,
                  color: star <= min
                      ? Colors.amber
                      : context.theme.unselectedWidgetColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Per-tracker filter rows, shown only when at least one tracker is logged in.
///
/// Single tracker: collapses heading + row into one "Tracked" toggle row.
/// Multiple trackers: "Tracked" section heading + one tri-state row per tracker.
class _TrackerFilterSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn =
        ref.watch(loggedInTrackersProvider).value ?? const [];
    if (loggedIn.isEmpty) return const SizedBox.shrink();

    if (loggedIn.length == 1) {
      // Single tracker: collapse heading + row into one tile.
      return _TrackerFilterTile(tracker: loggedIn.first, showName: false);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Text(
            context.l10n.filterTracked,
            style: context.theme.textTheme.labelLarge?.copyWith(
              color: context.theme.colorScheme.primary,
            ),
          ),
        ),
        for (final tracker in loggedIn)
          _TrackerFilterTile(tracker: tracker),
      ],
    );
  }
}

class _TrackerFilterTile extends ConsumerWidget {
  const _TrackerFilterTile({required this.tracker, this.showName = true});

  final dynamic tracker; // Fragment$TrackerDto
  final bool showName;

  static bool? _next(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pref = ref.watch(
        libraryMangaFilterTrackerProvider(trackerId: tracker.id as int));
    final activeColor = context.theme.colorScheme.primary;
    final excludeColor = context.theme.colorScheme.error;

    Widget icon;
    if (pref == null) {
      icon = Icon(Icons.check_box_outline_blank_rounded,
          color: context.theme.unselectedWidgetColor);
    } else if (pref == true) {
      icon = Icon(Icons.check_box_rounded, color: activeColor);
    } else {
      icon = Icon(Icons.disabled_by_default_rounded, color: excludeColor);
    }

    // Compact row matching the tri-state filter rows (24dp/10dp, icon + text).
    return InkWell(
      onTap: () => ref
          .read(libraryMangaFilterTrackerProvider(
                  trackerId: tracker.id as int)
              .notifier)
          .update(_next(pref)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                showName ? tracker.name as String : context.l10n.filterTracked,
                style: context.theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single row that enables/disables category filtering and provides an
/// "Edit" button to open the category include/exclude dialog.
class _CategoryFilterRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled =
        ref.watch(libraryFilterCategoriesProvider).ifNull(false);
    // Compact row matching the tri-state filter rows above (24dp/10dp, icon +
    // text) so Categories aligns with them instead of looking indented/nested
    // under the Lewd row. Icon leading (not a Material Checkbox) keeps the
    // title's x-position identical to the rows above.
    return InkWell(
      onTap: () => ref
          .read(libraryFilterCategoriesProvider.notifier)
          .update(!enabled),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            Icon(
              enabled
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: enabled
                  ? context.theme.colorScheme.primary
                  : context.theme.unselectedWidgetColor,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                context.l10n.categories,
                style: context.theme.textTheme.bodyMedium,
              ),
            ),
            if (enabled)
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _CategoryFilterDialog(),
                ),
                child: Text(context.l10n.edit),
              ),
          ],
        ),
      ),
    );
  }
}

/// Enables/disables user-tag filtering with an "Edit" button that opens the
/// tag include/exclude dialog. Mirrors [_CategoryFilterRow].
class _TagFilterRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(libraryFilterTagsProvider).ifNull(false);
    return InkWell(
      onTap: () =>
          ref.read(libraryFilterTagsProvider.notifier).update(!enabled),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            Icon(
              enabled
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: enabled
                  ? context.theme.colorScheme.primary
                  : context.theme.unselectedWidgetColor,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                context.l10n.tags,
                style: context.theme.textTheme.bodyMedium,
              ),
            ),
            if (enabled)
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _TagFilterDialog(),
                ),
                child: Text(context.l10n.edit),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tri-state each user tag: null = ignore, true = include (has this tag),
/// false = exclude (must not have this tag). Include is OR across selected tags.
class _TagFilterDialog extends ConsumerWidget {
  const _TagFilterDialog();

  static bool? _nextValue(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  Widget _leadingIcon(BuildContext context, bool? value) {
    if (value == null) {
      return Icon(Icons.check_box_outline_blank_rounded,
          color: context.theme.unselectedWidgetColor);
    } else if (value == true) {
      return Icon(Icons.check_box_rounded,
          color: context.theme.colorScheme.primary);
    } else {
      return Icon(Icons.disabled_by_default_rounded,
          color: context.theme.colorScheme.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(libraryTagListProvider);
    final includeSet =
        (ref.watch(libraryFilterTagsIncludeProvider) ?? const <String>[])
            .toSet();
    final excludeSet =
        (ref.watch(libraryFilterTagsExcludeProvider) ?? const <String>[])
            .toSet();

    bool? stateFor(String tag) {
      if (excludeSet.contains(tag)) return false;
      if (includeSet.contains(tag)) return true;
      return null;
    }

    void toggle(String tag) {
      final next = _nextValue(stateFor(tag));
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
    }

    final tags = tagsAsync.value ?? const <String>[];

    return AlertDialog(
      title: Text(context.l10n.tags),
      content: SizedBox(
        width: double.maxFinite,
        child: tagsAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : tags.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      context.l10n.noTagsYet,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: tags.length,
                    itemBuilder: (context, index) {
                      final tag = tags[index];
                      return ListTile(
                        leading: _leadingIcon(context, stateFor(tag)),
                        title: Text(tag),
                        onTap: () => toggle(tag),
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

/// Dialog that lets the user tri-state each category:
///   null  → not filtered (neither include nor exclude)
///   true  → include (manga must be in this category)
///   false → exclude (manga must NOT be in this category)
class _CategoryFilterDialog extends ConsumerWidget {
  const _CategoryFilterDialog();

  static bool? _nextValue(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  Widget _leadingIcon(BuildContext context, bool? value) {
    final activeColor = context.theme.colorScheme.primary;
    final excludeColor = context.theme.colorScheme.error;
    if (value == null) {
      return Icon(Icons.check_box_outline_blank_rounded,
          color: context.theme.unselectedWidgetColor);
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
      final current = stateFor(id);
      final next = _nextValue(current);

      // Remove from both sets first, then add to the appropriate one.
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
