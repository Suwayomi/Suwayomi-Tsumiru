// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/tri_state_filter_tile.dart';
import '../controller/updates_filter_controller.dart';

/// Filter rows for the Updates list. Same order Komikku uses — Downloaded,
/// Unread, Started, Bookmarked — and the same pills the library organizer uses.
class UpdatesFilterSheet extends ConsumerWidget {
  const UpdatesFilterSheet({super.key});

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
            header: context.l10n.filterHeaderDownloadStatus,
            provider: updatesFilterDownloadedProvider,
            onChanged: ref.read(updatesFilterDownloadedProvider.notifier).update,
            includedLabel: context.l10n.filterOptionDownloaded,
            excludedLabel: context.l10n.filterOptionNotDownloaded,
          ),
          TriStateFilterTile(
            header: context.l10n.filterHeaderReadStatus,
            provider: updatesFilterUnreadProvider,
            onChanged: ref.read(updatesFilterUnreadProvider.notifier).update,
            includedLabel: context.l10n.filterOptionUnread,
            excludedLabel: context.l10n.filterOptionRead,
          ),
          TriStateFilterTile(
            header: context.l10n.filterHeaderProgress,
            provider: updatesFilterStartedProvider,
            onChanged: ref.read(updatesFilterStartedProvider.notifier).update,
            includedLabel: context.l10n.filterOptionStarted,
            excludedLabel: context.l10n.filterOptionNotStarted,
          ),
          TriStateFilterTile(
            header: context.l10n.filterHeaderBookmarks,
            provider: updatesFilterBookmarkedProvider,
            onChanged: ref.read(updatesFilterBookmarkedProvider.notifier).update,
            includedLabel: context.l10n.filterOptionBookmarked,
            excludedLabel: context.l10n.filterOptionNotBookmarked,
          ),
        ],
      ),
    );
  }
}
