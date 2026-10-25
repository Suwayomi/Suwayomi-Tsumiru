// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../library/presentation/library/widgets/library_filter_segments.dart';
import '../controller/updates_filter_controller.dart';
import '../controller/updates_grouping_controller.dart';

class UpdatesFilterHeader extends ConsumerWidget {
  const UpdatesFilterHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(updatesHasActiveFiltersProvider);
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.filter,
            style: context.theme.textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: active
              ? () {
                  ref.read(updatesFilterDownloadedProvider.notifier).update(null);
                  ref.read(updatesFilterUnreadProvider.notifier).update(null);
                  ref.read(updatesFilterStartedProvider.notifier).update(null);
                  ref.read(updatesFilterBookmarkedProvider.notifier).update(null);
                }
              : null,
          child: Text(context.l10n.reset),
        ),
      ],
    );
  }
}

class UpdatesFilterSegments extends ConsumerWidget {
  const UpdatesFilterSegments({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LibraryTriStateSegment(
          heading: context.l10n.filterShortDownloaded,
          provider: updatesFilterDownloadedProvider,
          onChanged: ref.read(updatesFilterDownloadedProvider.notifier).update,
        ),
        LibraryTriStateSegment(
          heading: context.l10n.filterHeaderReadStatus,
          provider: updatesFilterUnreadProvider,
          onChanged: ref.read(updatesFilterUnreadProvider.notifier).update,
          includedLabel: context.l10n.filterOptionUnread,
          excludedLabel: context.l10n.filterOptionRead,
        ),
        LibraryTriStateSegment(
          heading: context.l10n.filterShortStarted,
          provider: updatesFilterStartedProvider,
          onChanged: ref.read(updatesFilterStartedProvider.notifier).update,
        ),
        LibraryTriStateSegment(
          heading: context.l10n.filterShortBookmarked,
          provider: updatesFilterBookmarkedProvider,
          onChanged: ref.read(updatesFilterBookmarkedProvider.notifier).update,
        ),
      ],
    );
  }
}

class UpdatesGroupingSegment extends ConsumerWidget {
  const UpdatesGroupingSegment({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupingMode =
        ref.watch(updatesGroupingModeProvider) ?? UpdatesGroupingMode.collapsed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(context.l10n.updatesGroupingLabel),
        AdaptiveSegments<UpdatesGroupingMode>(
          value: groupingMode,
          onChanged: (mode) =>
              ref.read(updatesGroupingModeProvider.notifier).update(mode),
          options: [
            for (final mode in const [
              UpdatesGroupingMode.collapsed,
              UpdatesGroupingMode.expanded,
              UpdatesGroupingMode.disabled,
            ])
              SegmentOption(value: mode, label: mode.toLocale(context)),
          ],
        ),
      ],
    );
  }
}

class UpdatesFilterPanel extends StatelessWidget {
  const UpdatesFilterPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [UpdatesFilterHeader(), UpdatesFilterSegments()],
        ),
      ),
    );
  }
}

class UpdatesDisplayModeSegment extends ConsumerWidget {
  const UpdatesDisplayModeSegment({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayMode =
        ref.watch(updatesDisplayModeProvider) ?? UpdatesDisplayMode.grid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterSectionHeading(context.l10n.displayMode),
        AdaptiveSegments<UpdatesDisplayMode>(
          value: displayMode,
          onChanged: (mode) =>
              ref.read(updatesDisplayModeProvider.notifier).update(mode),
          options: [
            for (final mode in UpdatesDisplayMode.values)
              SegmentOption(value: mode, label: mode.toLocale(context)),
          ],
        ),
      ],
    );
  }
}

class UpdatesDisplayPanel extends ConsumerWidget {
  const UpdatesDisplayPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayMode =
        ref.watch(updatesDisplayModeProvider) ?? UpdatesDisplayMode.grid;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const UpdatesDisplayModeSegment(),
            if (displayMode == UpdatesDisplayMode.list)
              const UpdatesGroupingSegment(),
          ],
        ),
      ),
    );
  }
}
