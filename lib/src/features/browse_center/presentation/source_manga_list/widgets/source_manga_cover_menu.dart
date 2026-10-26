// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../routes/navigation.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart'
    show ChapterMenuRow;
import '../../../../manga_book/presentation/manga_details/widgets/manga_description.dart';

Future<void> showSourceMangaCoverMenu({
  required BuildContext context,
  required WidgetRef ref,
  required RelativeRect position,
  required MangaDto manga,
  required VoidCallback onSelect,
  required ValueChanged<MangaDto> onAddToLibrary,
  bool addEnabled = true,
}) async {
  final inLibrary = manga.user.inLibrary.ifNull();
  await showMenu<void>(
    context: context,
    position: position,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: [
      PopupMenuItem<void>(
        onTap: () => MangaRoute(mangaId: manga.id).push(context),
        child: ChapterMenuRow(
          icon: FluentIcons.book_open_24_regular,
          label: context.l10n.open,
        ),
      ),
      if (!inLibrary)
        PopupMenuItem<void>(
          enabled: addEnabled,
          onTap: () => onAddToLibrary(manga),
          child: ChapterMenuRow(
            icon: FluentIcons.heart_24_regular,
            label: context.l10n.addToLibrary,
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<void>(
        onTap: onSelect,
        child: ChapterMenuRow(
          icon: FluentIcons.select_all_on_24_regular,
          label: context.l10n.select,
        ),
      ),
      PopupMenuItem<void>(
        onTap: () => openGlobalSearch(context, query: manga.title),
        child: ChapterMenuRow(
          icon: FluentIcons.search_24_regular,
          label: context.l10n.searchOtherSources,
        ),
      ),
      if (manga.realUrl.isNotBlank)
        PopupMenuItem<void>(
          onTap: () => MangaDescription.openInBrowser(context, ref, manga),
          child: ChapterMenuRow(
            icon: FluentIcons.globe_24_regular,
            label: context.l10n.openInBrowser,
          ),
        ),
    ],
    popUpAnimationStyle: context.motionStyle,
  );
}
