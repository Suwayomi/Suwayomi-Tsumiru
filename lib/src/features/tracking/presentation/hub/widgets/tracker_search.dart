// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/hooks/debounced_hook.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../widgets/search_field.dart';
import '../../../controller/manga_track_records_controller.dart';
import '../../../controller/tracker_search_controller.dart';
import '../../../data/graphql/__generated__/query.graphql.dart';
import '../../../data/tracker_repository.dart';

/// Task 7 — search for a remote entry and bind it to this manga.
class TrackerSearch extends HookConsumerWidget {
  const TrackerSearch({
    super.key,
    required this.mangaId,
    required this.mangaTitle,
    required this.tracker,
    required this.onBound,
  });

  final int mangaId;
  final String mangaTitle;
  final Fragment$TrackerDto tracker;
  final VoidCallback onBound;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawInput = useState(mangaTitle);
    // Debounce searchTracker calls or AniList/MAL rate-limits (429) and search looks broken.
    final query = useSettled(rawInput.value, const Duration(milliseconds: 400));
    final selected = useState<Fragment$TrackSearchDto?>(null);
    // Blocks selection/binding until results catch up with the typed query.
    final searchPending = rawInput.value != query;

    void onInput(String? value) {
      rawInput.value = value ?? '';
      // Drop any selection from the previous query so it can't get bound.
      selected.value = null;
    }

    // Don't fire a search for an empty query (e.g. the field was cleared).
    final resultsAsync = query.isEmpty
        ? null
        : ref.watch(searchTrackerProvider(trackerId: tracker.id, query: query));

    Future<void> bind({required bool private}) async {
      final entry = selected.value;
      if (entry == null) return;
      final result = await AsyncValue.guard(
        () => ref
            .read(trackerRepositoryProvider)
            .bind(
              mangaId: mangaId,
              trackerId: tracker.id,
              remoteId: entry.remoteId,
              private: private,
            ),
      );
      // Both branches touch ref; bail if the sheet was dismissed mid-flight.
      if (!context.mounted) return;
      if (result.hasError) {
        result.showToastOnError(ref.read(toastProvider));
        return;
      }
      ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
      ref.read(toastProvider)?.show(context.l10n.trackBindSuccess(tracker.name));
      onBound();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle.
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: context.theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Search field pre-filled with manga title (with tablet constraint & padding).
          SizedBox(
            width: context.isLargeTablet
                ? context.widthScale(scale: .5)
                : null,
            child: Padding(
              padding: KEdgeInsets.h16v4.size,
              child: SearchField(
                initialText: mangaTitle,
                hintText: context.l10n.search,
                autofocus: false,
                onSubmitted: onInput,
                onChanged: onInput,
              ),
            ),
          ),

          // Track / Track privately buttons (shown once a result is selected
          // and the search has settled).
          if (!searchPending && selected.value != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => bind(private: false),
                      child: Text(context.l10n.track),
                    ),
                  ),
                  if (tracker.supportsPrivateTracking) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => bind(private: true),
                        child: Text(context.l10n.trackPrivately),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Results list. Spinner while pending so nothing stale can be tapped.
          Flexible(
            child: query.isEmpty
                ? const SizedBox.shrink()
                : searchPending
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : resultsAsync!.showUiWhenData(context, (results) {
                    if (results.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(context.l10n.noSearchResults),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final result = results[index];
                        final isSelected =
                            selected.value?.remoteId == result.remoteId;
                        return _TrackSearchResultTile(
                          result: result,
                          isSelected: isSelected,
                          onTap: () {
                            selected.value = isSelected ? null : result;
                          },
                        );
                      },
                    );
                  }),
          ),
        ],
      ),
    );
  }
}

class _TrackSearchResultTile extends StatelessWidget {
  const _TrackSearchResultTile({
    required this.result,
    required this.isSelected,
    required this.onTap,
  });

  final Fragment$TrackSearchDto result;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected
            ? context.theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                result.coverUrl,
                width: 56,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 80,
                  color: context.theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_rounded),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Text details.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: context.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${result.publishingType} · ${result.publishingStatus}',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (result.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      result.summary,
                      style: context.textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: context.theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
