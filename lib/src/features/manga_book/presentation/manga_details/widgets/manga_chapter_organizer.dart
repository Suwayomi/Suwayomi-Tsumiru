// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import 'manga_chapter_display.dart';
import 'manga_chapter_filter.dart';
import 'manga_chapter_sort.dart';

class MangaChapterOrganizer extends StatelessWidget {
  const MangaChapterOrganizer({super.key, required this.mangaId});
  final int mangaId;
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: TabBar(
          // Fill alignment so the underline aligns under each tab (the global
          // theme's center alignment is for the scrollable category tabs).
          tabAlignment: TabAlignment.fill,
          tabs: [
            Tab(text: context.l10n.filter),
            Tab(text: context.l10n.sort),
            Tab(text: context.l10n.display),
          ],
        ),
        body: TabBarView(
          children: [
            MangaChapterFilter(mangaId: mangaId),
            const MangaChapterSort(),
            const MangaChapterDisplay(),
          ],
        ),
      ),
    );
  }
}
