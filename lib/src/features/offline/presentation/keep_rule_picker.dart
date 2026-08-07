// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../data/offline_database.dart';

/// Rolling-buffer sizes offered for the "keep next N unread" rule.
const kOfflineBufferSizes = [5, 10, 25];

/// Bottom sheet that lets the user choose an offline keep-rule (how much of a
/// series to hold on the device). Returns the chosen rule + count, or null if
/// dismissed. Shared by the per-series sheet, the library multi-select Offline
/// action, and the download-subscriptions management page so they stay in sync.
Future<({OfflineKeepRule rule, int count})?> pickOfflineKeepRule(
  BuildContext context,
) {
  return showModalBottomSheet<({OfflineKeepRule rule, int count})>(
    context: context,
    showDragHandle: true,
    // Scroll-controlled and scrollable: a default sheet is capped at 9/16 of
    // the space it is given, and the "Updating library" strip is a sibling of
    // the page content, so it shrinks that space from under it.
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final n in kOfflineBufferSizes)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text(sheetContext.l10n.keepOfflineNextUnread(n)),
                onTap: () => Navigator.pop(sheetContext, (
                  rule: OfflineKeepRule.nUnread,
                  count: n,
                )),
              ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(sheetContext.l10n.keepOfflineAllUnread),
              onTap: () => Navigator.pop(sheetContext, (
                rule: OfflineKeepRule.allUnread,
                count: 3,
              )),
            ),
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: Text(sheetContext.l10n.keepOfflineAll),
              onTap: () => Navigator.pop(sheetContext, (
                rule: OfflineKeepRule.all,
                count: 3,
              )),
            ),
          ],
        ),
      ),
    ),
  );
}
