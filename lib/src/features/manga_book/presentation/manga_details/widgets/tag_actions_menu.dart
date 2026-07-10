// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../library/presentation/library/controller/library_controller.dart';

/// Komikku's tag-chip actions (MangaInfoHeader.kt:399-425): a dropdown anchored
/// at the tapped chip offering Search (a plain library search for the tag, as
/// Komikku's onTagSearch → HomeScreen.search does), Global search (all sources),
/// and Copy to clipboard. [context] must be the chip's own context so the menu
/// anchors to it.
Future<void> showTagActionsMenu(
  BuildContext context,
  WidgetRef ref, {
  required String tag,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );

  final action = await showMenu<String>(
    context: context,
    position: position,
    items: [
      PopupMenuItem(value: 'search', child: Text(context.l10n.search)),
      PopupMenuItem(value: 'global', child: Text(context.l10n.globalSearch)),
      PopupMenuItem(
          value: 'copy', child: Text(context.l10n.copyToClipboard)),
    ],
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'search':
      // Komikku's "Search": open the library filtered to the tag.
      ref.read(libraryQueryProvider.notifier).update(tag);
      const LibraryRoute(categoryId: 0).go(context);
    case 'global':
      GlobalSearchRoute(query: tag).push(context);
    case 'copy':
      Clipboard.setData(ClipboardData(text: tag));
      ref.read(toastProvider)?.show(context.l10n.copiedToClipboard);
  }
}
