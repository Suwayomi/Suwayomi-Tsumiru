// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/launch_url_in_web.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/theme/brand.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/manga/manga_model.dart';
import '../reader_mode/infinity_continuous/measure_size.dart';
import 'chrome_extents.dart';
import 'reader_bookmark_button.dart';

/// The reader's top chrome bar — mirrors the content that was previously in
/// [ReaderWrapper]'s [Scaffold.appBar] slot.
///
/// This is a plain [Material]+[Row] widget, NOT a [Scaffold.appBar], so it can
/// live in the body [Stack] and be driven by a shared animation controller.
/// Visual output is byte-identical to the old AppBar.
class ReaderTopBar extends ConsumerWidget {
  const ReaderTopBar({
    super.key,
    required this.manga,
    required this.chapter,
    required this.onBack,
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Compute the system status-bar inset so the bar sits below it.
    final view = View.of(context);
    final systemTopInset = view.viewPadding.top / view.devicePixelRatio;

    // Wrap the bar in MeasureSize so its resting laid-out height is reported to
    // chromeExtentsNotifierProvider.  MeasureSize already defers via
    // addPostFrameCallback, so we are safely outside the build phase when
    // the provider.update() call runs. The SlideTransition that animates this
    // bar uses a Transform (no relayout), so MeasureSize always sees the
    // resting height — never a mid-animation partial height.
    return MeasureSize(
      onChange: (size) {
        final current = ref.read(chromeExtentsNotifierProvider);
        // size.height is the full Material height: it already includes the
        // status-bar padding baked in via Padding(top: systemTopInset) below.
        // Adding systemTopInset again would double-count it, pushing the side
        // seekbar ~44 dp too low on notch devices.  Mirror the bottom bar:
        //   its onChange uses `bottomInset: size.height` for
        //   the same reason — the nav-bar Padding is inside the measured subtree.
        final next = ChromeExtents(
          topInset: size.height,
          bottomInset: current.bottomInset,
        );
        ref.read(chromeExtentsNotifierProvider.notifier).update(next);
      },
      child: Material(
        // Shared chrome surface; the Material fills behind the status bar.
        color: readerNavSurface(context.theme.colorScheme),
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.only(top: systemTopInset),
          child: Row(
            children: [
              // Back button (mirrors AppBar's leading).
              IconButton(
                onPressed: onBack,
                icon: const BackButtonIcon(),
              ),
              // Title + subtitle (mirrors AppBar's title ListTile).
              Expanded(
                child: ListTile(
                  title: (manga.title).isNotBlank
                      ? Text(
                          manga.title,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  subtitle: (chapter.name).isNotBlank
                      ? Text(
                          chapter.name,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // Actions (mirrors AppBar.actions).
              ReaderBookmarkButton(
                chapterId: chapter.id,
                fallbackIsBookmarked: chapter.isBookmarked,
              ),
              chapter.realUrl.isBlank
                  ? const SizedBox.shrink()
                  : IconButton(
                      onPressed: () async {
                        launchUrlInWeb(
                          context,
                          (chapter.realUrl ?? ""),
                          ref.read(toastProvider),
                        );
                      },
                      icon: const Icon(Icons.public_rounded),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
