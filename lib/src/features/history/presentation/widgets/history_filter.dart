// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/tri_state_filter_tile.dart';
import '../history_controller.dart';

/// Filter rows for the History list, matching Komikku's three: unfinished
/// series, unfinished chapter, and library membership.
class HistoryFilterSheet extends ConsumerWidget {
  const HistoryFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Text(
              context.l10n.filter,
              style: context.textTheme.titleMedium,
            ),
          ),
          TriStateFilterTile(
            header: context.l10n.filterHeaderSeries,
            provider: historyFilterUnfinishedSeriesProvider,
            onChanged: ref
                .read(historyFilterUnfinishedSeriesProvider.notifier)
                .update,
            includedLabel: context.l10n.filterOptionUnfinished,
            excludedLabel: context.l10n.filterOptionFinished,
          ),
          TriStateFilterTile(
            header: context.l10n.filterHeaderReadStatus,
            provider: historyFilterUnreadProvider,
            onChanged: ref.read(historyFilterUnreadProvider.notifier).update,
            includedLabel: context.l10n.filterOptionUnread,
            excludedLabel: context.l10n.filterOptionRead,
          ),
          TriStateFilterTile(
            header: context.l10n.filterHeaderLibrary,
            provider: historyFilterInLibraryProvider,
            onChanged: ref.read(historyFilterInLibraryProvider.notifier).update,
            includedLabel: context.l10n.filterOptionInLibrary,
            excludedLabel: context.l10n.filterOptionNotInLibrary,
          ),
        ],
      ),
    );
  }
}
