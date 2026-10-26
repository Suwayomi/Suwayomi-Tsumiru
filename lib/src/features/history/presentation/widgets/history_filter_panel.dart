// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../library/presentation/library/widgets/library_filter_segments.dart';
import '../history_controller.dart';

class HistoryFilterPanel extends ConsumerWidget {
  const HistoryFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(historyHasActiveFiltersProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                        ref
                            .read(
                              historyFilterUnfinishedSeriesProvider.notifier,
                            )
                            .update(null);
                        ref
                            .read(historyFilterUnreadProvider.notifier)
                            .update(null);
                        ref
                            .read(historyFilterInLibraryProvider.notifier)
                            .update(null);
                      }
                    : null,
                child: Text(context.l10n.reset),
              ),
            ],
          ),
          FilterSectionHeading(context.l10n.filterHeaderSeries),
          AdaptiveSegments<bool?>(
            value: ref.watch(historyFilterUnfinishedSeriesProvider),
            onChanged: ref
                .read(historyFilterUnfinishedSeriesProvider.notifier)
                .update,
            options: [
              SegmentOption(value: null, label: context.l10n.filterStateAny),
              SegmentOption(
                value: true,
                label: context.l10n.filterOptionUnfinished,
              ),
              SegmentOption(
                value: false,
                label: context.l10n.filterOptionFinished,
              ),
            ],
          ),
          FilterSectionHeading(context.l10n.filterHeaderReadStatus),
          AdaptiveSegments<bool?>(
            value: ref.watch(historyFilterUnreadProvider),
            onChanged: ref.read(historyFilterUnreadProvider.notifier).update,
            options: [
              SegmentOption(value: null, label: context.l10n.filterStateAny),
              SegmentOption(
                value: true,
                label: context.l10n.filterOptionUnread,
              ),
              SegmentOption(value: false, label: context.l10n.filterOptionRead),
            ],
          ),
          FilterSectionHeading(context.l10n.filterHeaderLibrary),
          AdaptiveSegments<bool?>(
            value: ref.watch(historyFilterInLibraryProvider),
            onChanged: ref.read(historyFilterInLibraryProvider.notifier).update,
            options: [
              SegmentOption(value: null, label: context.l10n.filterStateAny),
              SegmentOption(
                value: true,
                label: context.l10n.filterOptionInLibrary,
              ),
              SegmentOption(
                value: false,
                label: context.l10n.filterOptionNotInLibrary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
