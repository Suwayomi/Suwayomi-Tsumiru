// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../domain/chapter_batch/chapter_batch_model.dart';
import '../../../../widgets/chapter_actions/single_chapter_action_icon.dart';
import '../../controller/reader_controller.dart';

class ReaderBookmarkButton extends ConsumerWidget {
  const ReaderBookmarkButton({
    super.key,
    required this.chapterId,
    required this.fallbackIsBookmarked,
  });

  final int chapterId;
  final bool fallbackIsBookmarked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBookmarked = ref.watch(
          chapterProvider(chapterId: chapterId)
              .select((c) => c.valueOrNull?.isBookmarked),
        ) ??
        fallbackIsBookmarked;
    return SingleChapterActionIcon(
      icon: isBookmarked
          ? Icons.bookmark_rounded
          : Icons.bookmark_outline_rounded,
      chapterId: chapterId,
      change: ChapterChange(isBookmarked: !isBookmarked),
      refresh: () => ref.refresh(chapterProvider(chapterId: chapterId).future),
    );
  }
}
