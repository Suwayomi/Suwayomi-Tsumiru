// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/download_presets_menu.dart';
import '../../../../account/data/account_providers.dart';
import '../../../data/downloads/downloads_repository.dart';
import '../../../domain/chapter/chapter_download_presets.dart';
import '../../../domain/chapter/chapter_model.dart';
import 'manga_action_button.dart';

class ChapterDownloadPresetsButton extends HookConsumerWidget {
  const ChapterDownloadPresetsButton({
    super.key,
    required this.chapterList,
    required this.refresh,
    this.actionRow = false,
  });

  /// Chapter list for preset computation: filtered to preferred scanlators
  /// when a scanlator preference is active, otherwise the full raw list.
  final AsyncValue<List<ChapterDto>?> chapterList;
  final bool actionRow;

  /// Callback to re-fetch chapters after a successful enqueue.
  /// Mirrors the signature used elsewhere in manga_details_screen.
  final Future<void> Function(bool) refresh;

  Future<void> _handlePreset(
    BuildContext context,
    WidgetRef ref,
    DownloadPreset preset,
  ) async {
    final chapters = chapterList.value ?? const [];
    final candidates = [
      for (final c in chapters)
        ChapterDownloadCandidate(
          id: c.id,
          chapterNumber: c.chapterNumber,
          isRead: c.user.isRead,
          isDownloaded: c.user.isDownloaded,
        ),
    ];

    final ids = chaptersToQueueForPreset(candidates, preset);

    if (ids.isEmpty) {
      ref.read(toastProvider)?.show(context.l10n.nothingToDownload);
      return;
    }

    final result = await AsyncValue.guard(
      () => ref
          .read(downloadsRepositoryProvider)
          .addChaptersBatchToDownloadQueue(ids),
    );
    if (context.mounted) {
      result.showToastOnError(ref.read(toastProvider));
      if (!result.hasError) ref.read(toastProvider)?.show(context.l10n.queued);
    }
    // Enqueuing a download doesn't change the source's chapter list — refresh
    // from the server's stored chapters (updated download state), no re-scrape.
    if (context.mounted) await refresh(false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final menuKey = useMemoized(
      () => GlobalKey<PopupMenuButtonState<DownloadPreset>>(),
    );
    if (actionRow) {
      return PopupMenuButton<DownloadPreset>(
        key: menuKey,
        enabled: canDownload,
        tooltip: canDownload
            ? context.l10n.downloadToServer
            : context.l10n.accountPermissionDenied,
        onSelected: (preset) => _handlePreset(context, ref, preset),
        itemBuilder: (context) => [
          for (final preset in DownloadPreset.values)
            PopupMenuItem(
              value: preset,
              child: Text(downloadPresetLabel(context, preset)),
            ),
        ],
        popUpAnimationStyle: context.motionStyle,
        child: MangaActionButton(
          icon: const Icon(Icons.cloud_download_outlined),
          label: context.l10n.server,
          onPressed: canDownload
              ? () => menuKey.currentState?.showButtonMenu()
              : null,
        ),
      );
    }
    return DownloadPresetsMenu(
      enabled: canDownload,
      onSelected: (preset) => _handlePreset(context, ref, preset),
    );
  }
}
