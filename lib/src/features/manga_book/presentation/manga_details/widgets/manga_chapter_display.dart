// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../controller/manga_details_controller.dart';

class MangaChapterDisplay extends ConsumerWidget {
  const MangaChapterDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ChapterDisplay display =
        ref.watch(mangaChapterDisplayModeProvider) ?? DBKeys.chapterDisplay.initial;
    return ListView(
      children: [
        const Divider(height: .5),
        for (final ChapterDisplay mode in ChapterDisplay.values)
          RadioListTile<ChapterDisplay>(
            title: Text(mode.toLocale(context)),
            value: mode,
            groupValue: display,
            onChanged: (value) => ref
                .read(mangaChapterDisplayModeProvider.notifier)
                .update(value),
          ),
      ],
    );
  }
}
