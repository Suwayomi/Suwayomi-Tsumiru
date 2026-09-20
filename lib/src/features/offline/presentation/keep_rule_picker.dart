// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../account/data/account_providers.dart';
import '../data/offline_database.dart';

/// Rolling-buffer sizes offered for the "keep next N unread" rule.
const kOfflineBufferSizes = [5, 10, 25];

/// Bottom sheet that lets the user choose an offline keep-rule (how much of a
/// series to hold on the device). Returns the chosen rule + count + whether
/// local files should also be deleted, or null if dismissed.
///
/// `remove: true` is only set for the "Remove from device" option — callers
/// must also delete local chapters when this flag is set. All other options
/// set `remove: false` and only adjust the keep-rule.
///
/// The keep options need the account's download permission; stopping a rule
/// and freeing device space do not, so they stay available to every account.
Future<({OfflineKeepRule rule, int count, bool remove})?> pickOfflineKeepRule(
  BuildContext context,
) {
  return showModalBottomSheet<({OfflineKeepRule rule, int count, bool remove})>(
    context: context,
    showDragHandle: true,
    // Scroll-controlled and scrollable: a default sheet is capped at 9/16 of
    // the space it is given, and the "Updating library" strip is a sibling of
    // the page content, so it shrinks that space from under it.
    isScrollControlled: true,
    builder: (sheetContext) => Consumer(
      builder: (context, sheetRef, _) {
        final canDownload = sheetRef
            .watch(settledAccountAccessProvider)
            .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!canDownload)
                  ListTile(
                    subtitle: Text(context.l10n.accountPermissionDenied),
                  ),
                for (final n in kOfflineBufferSizes)
                  ListTile(
                    leading: const Icon(Icons.bookmark_add_outlined),
                    title: Text(sheetContext.l10n.keepOfflineNextUnread(n)),
                    onTap: canDownload
                        ? () => Navigator.pop(sheetContext, (
                            rule: OfflineKeepRule.nUnread,
                            count: n,
                            remove: false,
                          ))
                        : null,
                  ),
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(sheetContext.l10n.keepOfflineAllUnread),
                  onTap: canDownload
                      ? () => Navigator.pop(sheetContext, (
                          rule: OfflineKeepRule.allUnread,
                          count: 3,
                          remove: false,
                        ))
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.library_books_outlined),
                  title: Text(sheetContext.l10n.keepOfflineAll),
                  onTap: canDownload
                      ? () => Navigator.pop(sheetContext, (
                          rule: OfflineKeepRule.all,
                          count: 3,
                          remove: false,
                        ))
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bookmark_remove_outlined),
                  title: Text(sheetContext.l10n.manageDownloadsStopKeep),
                  onTap: () => Navigator.pop(sheetContext, (
                    rule: OfflineKeepRule.off,
                    count: 0,
                    remove: false,
                  )),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: sheetContext.theme.colorScheme.error,
                  ),
                  title: Text(
                    sheetContext.l10n.manageDownloadsStopDelete,
                    style: TextStyle(
                      color: sheetContext.theme.colorScheme.error,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, (
                    rule: OfflineKeepRule.off,
                    count: 0,
                    remove: true,
                  )),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
