// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/emoticons.dart';
import '../../../widgets/server_image.dart';
import '../data/offline_download_providers.dart';
import '../data/offline_repository.dart';
import 'offline_settings_format.dart';

/// The "On device" segment of the Downloads tab: every series with chapters
/// saved on this device, with per-series chapter count + size, plus total
/// usage. Live — updates as background downloads complete or are removed.
class OfflineFilesView extends ConsumerWidget {
  const OfflineFilesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(offlineEnabledProvider)) {
      return Center(child: Text(context.l10n.offlineNotAvailable));
    }
    final series =
        ref.watch(offlineDownloadedSeriesProvider).valueOrNull ?? const [];
    final totalBytes = ref.watch(offlineUsageBytesProvider).valueOrNull ?? 0;
    if (series.isEmpty) {
      return Emoticons(title: context.l10n.offlineNoFiles);
    }
    return ListView.builder(
      itemCount: series.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text(context.l10n.offlineStorageUsage),
            trailing: Text(formatBytes(totalBytes)),
          );
        }
        final s = series[index - 1];
        final downloading = s.inFlight > 0;
        return ListTile(
          leading: SizedBox(
            width: 40,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ServerImage(
                imageUrl: s.manga.thumbnailUrl ?? '',
                fit: BoxFit.cover,
              ),
            ),
          ),
          title: Text(s.manga.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(downloading
              ? '${context.l10n.offlineDownloadingCount(s.inFlight)} · ${context.l10n.nChapters(s.count)}'
              : '${context.l10n.nChapters(s.count)} · ${formatBytes(s.bytes)}'),
          trailing: downloading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          onTap: () => MangaRoute(mangaId: s.manga.id).push(context),
        );
      },
    );
  }
}
