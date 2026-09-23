// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../features/manga_book/domain/chapter/chapter_download_presets.dart';
import '../utils/extensions/custom_extensions.dart';

String downloadPresetLabel(BuildContext context, DownloadPreset preset) =>
    switch (preset) {
      DownloadPreset.nextChapter => context.l10n.downloadNextChapter,
      DownloadPreset.next5 => context.l10n.downloadNextChaptersN(5),
      DownloadPreset.next10 => context.l10n.downloadNextChaptersN(10),
      DownloadPreset.next25 => context.l10n.downloadNextChaptersN(25),
      DownloadPreset.unread => context.l10n.downloadUnreadChapters,
      DownloadPreset.all => context.l10n.downloadAllChapters,
    };

class DownloadPresetsMenu extends StatelessWidget {
  const DownloadPresetsMenu({
    super.key,
    required this.onSelected,
    this.enabled = true,
  });

  final ValueChanged<DownloadPreset>? onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final canDownload = enabled && onSelected != null;
    return PopupMenuButton<DownloadPreset>(
      enabled: canDownload,
      icon: const Icon(Icons.cloud_download_outlined),
      tooltip: canDownload
          ? context.l10n.downloadToServer
          : context.l10n.accountPermissionDenied,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final preset in DownloadPreset.values)
          PopupMenuItem(
            value: preset,
            child: Text(downloadPresetLabel(context, preset)),
          ),
      ],
    );
  }
}
