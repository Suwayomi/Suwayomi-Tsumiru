// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../offline/data/offline_settings_providers.dart';
import '../../../offline/presentation/offline_files_view.dart';
import '../../domain/downloads/downloads_model.dart';
import 'controller/downloads_controller.dart';
import 'widgets/download_progress_list_tile.dart';
import 'widgets/downloads_fab.dart';

class DownloadsScreen extends HookConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsChapterIds = ref.watch(downloadsChapterIdsProvider);
    final downloadsGlobalStatus = ref.watch(downloaderStateProvider);
    final showDownloadsFAB = ref.watch(showDownloadsFABProvider);
    // Own the tab controller so the FAB can be tab-contextual: the server queue
    // pause on the Server tab, the on-device pause on the On-device tab.
    final tabController = useTabController(initialLength: 2);
    useListenable(tabController);
    final onDeviceTab = tabController.index == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.downloads),
        bottom: TabBar(
          controller: tabController,
          // Fill alignment so the underline aligns under each tab (the global
          // theme's center alignment is for the scrollable category tabs).
          tabAlignment: TabAlignment.fill,
          tabs: [
            Tab(text: context.l10n.downloadsServerTab),
            Tab(text: context.l10n.downloadsOnDeviceTab),
          ],
        ),
        actions: [
          if (!onDeviceTab && (downloadsChapterIds).isNotBlank)
            IconButton(
              onPressed: () => AsyncValue.guard(
                ref.read(downloadsMapProvider.notifier).clearAll,
              ),
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      floatingActionButton: onDeviceTab
          ? const OfflineDownloadsFab()
          : (showDownloadsFAB
              ? DownloadsFab(
                  status: downloadsGlobalStatus.value ??
                      DownloaderState.STARTED)
              : null),
      body: TabBarView(
        controller: tabController,
        children: [
          _ServerDownloads(
            downloadsChapterIds: downloadsChapterIds,
            downloadsGlobalStatus: downloadsGlobalStatus,
          ),
          const OfflineFilesView(),
        ],
      ),
    );
  }
}

/// Pause/Resume control for ON-DEVICE downloads, shown on the Downloads →
/// On device tab (mirrors the server [DownloadsFab]). Hidden when there's
/// nothing queued/downloading; flips between Pause and Resume otherwise.
class OfflineDownloadsFab extends ConsumerWidget {
  const OfflineDownloadsFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPending = ref.watch(offlineHasPendingProvider).value ?? false;
    final paused = ref.watch(offlineDownloadsPausedProvider) ?? false;
    // Hide when idle (no pending work) — paused-but-idle included; the next
    // enqueue flips it back to Resume.
    if (!hasPending) return const SizedBox.shrink();
    return FloatingActionButton.extended(
      icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
      label: Text(paused ? context.l10n.resume : context.l10n.pause),
      onPressed: () => setOfflineDownloadsPaused(ref, !paused),
    );
  }
}

/// The existing server download-queue view (the "Server" tab).
class _ServerDownloads extends ConsumerWidget {
  const _ServerDownloads({
    required this.downloadsChapterIds,
    required this.downloadsGlobalStatus,
  });

  final List<int> downloadsChapterIds;
  final AsyncValue<DownloaderState?> downloadsGlobalStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    return downloadsGlobalStatus.showUiWhenData(
        context,
        (data) {
          if (data == null) {
            return Emoticons(title: context.l10n.errorSomethingWentWrong);
          } else if (downloadsChapterIds.isBlank) {
            return Emoticons(title: context.l10n.noDownloads);
          } else {
            final downloadsCount =
                (downloadsChapterIds.length).getValueOnNullOrNegative();
            return RefreshIndicator(
              onRefresh: () => ref.refresh(downloadStatusProvider.future),
              child: ListView.builder(
                itemBuilder: (context, index) {
                  if (index == downloadsCount) return const Gap(104);
                  final chapterId = downloadsChapterIds[index];
                  return DownloadProgressListTile(
                    key: ValueKey("$chapterId"),
                    index: index,
                    downloadsCount: downloadsCount,
                    chapterId: chapterId,
                    toast: toast,
                  );
                },
                itemCount: downloadsCount + 1,
              ),
            );
          }
        },
        showGenericError: true,
    );
  }
}
