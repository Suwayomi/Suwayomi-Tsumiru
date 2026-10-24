// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/emoticons.dart';
import '../../../widgets/server_image.dart';
import '../../account/data/account_providers.dart';
import '../data/offline_database.dart';
import '../data/offline_download_providers.dart';
import 'offline_action_confirmations.dart';
import 'offline_settings_format.dart';

class OfflineSeriesChaptersScreen extends ConsumerWidget {
  const OfflineSeriesChaptersScreen({
    super.key,
    required this.mangaId,
    required this.mangaTitle,
    required this.thumbnailUrl,
  });

  final int mangaId;
  final String mangaTitle;
  final String? thumbnailUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(offlineChaptersForMangaProvider(mangaId));
    final chapters = chaptersAsync.value ?? const [];

    final active =
        chapters
            .where(
              (c) =>
                  c.deviceState == OfflineDeviceState.queued ||
                  c.deviceState == OfflineDeviceState.downloading,
            )
            .toList()
          ..sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));

    final downloaded =
        chapters
            .where((c) => c.deviceState == OfflineDeviceState.downloaded)
            .toList()
          ..sort((a, b) => b.chapterIndex.compareTo(a.chapterIndex));

    final failed =
        chapters
            .where((c) => c.deviceState == OfflineDeviceState.error)
            .toList()
          ..sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));

    final hasAny =
        active.isNotEmpty || downloaded.isNotEmpty || failed.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: thumbnailUrl != null
                  ? ServerImage(
                      imageUrl: thumbnailUrl!,
                      fit: BoxFit.cover,
                      size: const Size(32, 42),
                    )
                  : const Icon(Icons.book_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.offlineChaptersScreenTitle,
                    style: context.textTheme.titleMedium,
                  ),
                  Text(
                    mangaTitle,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: !hasAny
          ? Emoticons(title: context.l10n.offlineChaptersEmpty)
          : ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader(context.l10n.offlineChaptersActiveSection),
                  for (final ch in active) _ActiveChapterTile(chapter: ch),
                ],

                if (downloaded.isNotEmpty) ...[
                  _SectionHeader(context.l10n.offlineChaptersDownloadedSection),
                  for (final ch in downloaded)
                    _DownloadedChapterTile(chapter: ch, mangaId: mangaId),
                ],

                if (failed.isNotEmpty) ...[
                  _SectionHeader(context.l10n.offlineChaptersErrorSection),
                  for (final ch in failed) _FailedChapterTile(chapter: ch),
                ],
              ],
            ),
    );
  }
}


class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: context.textTheme.labelMedium?.copyWith(
          color: context.theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}


class _ActiveChapterTile extends ConsumerWidget {
  const _ActiveChapterTile({required this.chapter});

  final OfflineChapter chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDownloading = chapter.deviceState == OfflineDeviceState.downloading;
    final progress = ref.watch(offlineChapterProgressProvider(chapter.id));

    Widget leading;
    if (isDownloading) {
      leading = SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              value: (progress == null || progress <= 0) ? null : progress,
            ),
          ),
        ),
      );
    } else {
      leading = Icon(
        Icons.schedule_rounded,
        color: context.theme.colorScheme.onSurfaceVariant,
      );
    }

    final subtitle = isDownloading
        ? progress != null && progress > 0
              ? '${(progress * 100).round()}%'
              : context.l10n.offlineDownloadAction
        : context.l10n.offlineChaptersQueued;

    return ListTile(
      leading: leading,
      title: Text(chapter.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      onTap: () => deleteChapterFromDevice(ref, chapter.id),
    );
  }
}


class _DownloadedChapterTile extends ConsumerWidget {
  const _DownloadedChapterTile({required this.chapter, required this.mangaId});

  final OfflineChapter chapter;
  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRead = chapter.isRead;

    return ListTile(
      leading: Icon(
        Icons.offline_pin_rounded,
        color: isRead
            ? context.theme.colorScheme.onSurfaceVariant
            : context.theme.colorScheme.primary,
      ),
      title: Text(
        chapter.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isRead ? context.theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: chapter.bytes > 0
          ? Text(
              formatBytes(chapter.bytes),
              style: TextStyle(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: IconButton(
        tooltip: context.l10n.offlineChapterDelete,
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: () => confirmDeleteChapterFromDevice(ref, chapter.id),
      ),
      onTap: () => ReaderRoute(
        mangaId: mangaId,
        chapterId: chapter.id,
        showReaderLayoutAnimation: false,
      ).push(context),
    );
  }
}


class _FailedChapterTile extends ConsumerWidget {
  const _FailedChapterTile({required this.chapter});

  final OfflineChapter chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    return ListTile(
      leading: Icon(
        Icons.error_outline_rounded,
        color: context.theme.colorScheme.error,
      ),
      title: Text(chapter.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: canDownload ? null : Text(context.l10n.accountPermissionDenied),
      trailing: TextButton.icon(
        icon: const Icon(Icons.replay_rounded, size: 18),
        label: Text(context.l10n.offlineChapterRetry),
        onPressed: canDownload
            ? () => saveChapterToDevice(ref, chapter.id)
            : null,
      ),
    );
  }
}
