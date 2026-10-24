// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/launch_url_in_web.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/platform/platform_runtime.dart';
import '../../../../../../utils/theme/brand.dart';
import '../../../../../../widgets/server_image.dart';
import '../../../../../settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/manga/manga_model.dart';
import '../../../manga_details/server_web_url.dart';
import '../../utils/koreader_progress_actions.dart';
import 'reader_bookmark_button.dart';

/// Measure this bar together with ReaderUtilsBar so expanded controls are included in the top inset.
class ReaderTopBar extends ConsumerWidget {
  const ReaderTopBar({
    super.key,
    required this.manga,
    required this.chapter,
    required this.onBack,
    required this.onJump,
    required this.pageCount,
    required this.currentPage,
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final VoidCallback onBack;
  final ValueChanged<int> onJump;
  final int pageCount;
  final int currentPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Status-bar inset the reader's SafeArea hasn't already applied.
    final connected =
        koSyncOnline(ref) &&
        ref.watch(koSyncStatusProvider).value?.isLoggedIn == true;
    final link = chapter.realUrl.isNotBlank ? chapter.realUrl : chapter.url;
    final serverMangaUrl = serverMangaWebUrl(ref, manga.id);
    final systemTopInset = MediaQuery.viewPaddingOf(context).top;

    return Material(
      color: readerNavSurface(context.theme.colorScheme),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.only(top: systemTopInset),
        child: Row(
          children: [
            IconButton(onPressed: onBack, icon: const BackButtonIcon()),
            Expanded(
              child: ListTile(
                title: (manga.title).isNotBlank
                    ? Text(manga.title, overflow: TextOverflow.ellipsis)
                    : null,
                subtitle: (chapter.name).isNotBlank
                    ? Text(chapter.name, overflow: TextOverflow.ellipsis)
                    : null,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) async {
                switch (action) {
                  case 'retry':
                    await retryFailedReaderPages(ref);
                  case 'web':
                    if (serverMangaUrl != null) {
                      launchUrlInWeb(
                        context,
                        '${serverMangaUrl.substring(0, serverMangaUrl.lastIndexOf('/manga/'))}/api/v1/webview#$link',
                        ref.read(toastProvider),
                      );
                    }
                  case 'share':
                    if (link.isBlank) return;
                    if (kIsWeb || isDesktopPlatform) {
                      await Clipboard.setData(ClipboardData(text: link!));
                      if (context.mounted) {
                        ref
                            .read(toastProvider)
                            ?.show(context.l10n.copiedToClipboard);
                      }
                    } else {
                      await SharePlus.instance.share(
                        ShareParams(uri: Uri.parse(link!), title: chapter.name),
                      );
                    }
                  case 'push':
                  case 'pull':
                    await syncKoReaderChapter(
                      context: context,
                      ref: ref,
                      chapter: chapter,
                      push: action == 'push',
                      pageCount: pageCount,
                      currentPage: currentPage,
                      onJump: onJump,
                    );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'retry',
                  child: Text(context.l10n.retryErroredPages),
                ),
                PopupMenuItem(
                  value: 'web',
                  enabled: serverMangaUrl != null && link.isNotBlank,
                  child: Text(context.l10n.openChapterInWebView),
                ),
                if (link.isNotBlank)
                  PopupMenuItem(
                    value: 'share',
                    child: Text(context.l10n.shareChapterLink),
                  ),
                if (connected) ...[
                  PopupMenuItem(
                    value: 'push',
                    enabled: koSyncOnline(ref),
                    child: Text(context.l10n.pushKoReaderProgress),
                  ),
                  PopupMenuItem(
                    value: 'pull',
                    enabled: koSyncOnline(ref),
                    child: Text(context.l10n.pullKoReaderProgress),
                  ),
                ],
              ],
            ),
            ReaderBookmarkButton(
              chapterId: chapter.id,
              fallbackIsBookmarked: chapter.user.isBookmarked,
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
    );
  }
}
