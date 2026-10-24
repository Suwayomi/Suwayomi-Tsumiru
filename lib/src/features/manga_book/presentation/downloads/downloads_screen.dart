// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../account/data/account_providers.dart';
import '../../../offline/data/offline_download_providers.dart';
import '../../../offline/data/offline_settings_providers.dart';
import '../../../offline/presentation/offline_files_view.dart';
import '../../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../../quick_open/presentation/unified_search/unified_search_providers.dart';
import '../../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
import '../../data/downloads/downloads_repository.dart';
import '../../domain/downloads/downloads_model.dart';
import '../../domain/downloads_queue/downloads_queue_model.dart';
import 'controller/downloads_controller.dart';
import 'widgets/download_progress_list_tile.dart';
import 'widgets/downloads_fab.dart';

class DownloadsScreen extends HookConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final downloadsChapterIds = ref.watch(downloadsChapterIdsProvider);
    final queueStatus = ref.watch(downloadStatusProvider);
    final downloaderRunState = ref.watch(downloaderRunStateProvider);
    final showDownloadsFAB = ref.watch(showDownloadsFABProvider);
    final erroredChapterIds = ref.watch(
      downloadsMapProvider.select(
        (map) => [
          for (final d in map.values)
            if (d.state == DownloadState.ERROR) d.chapter.id,
        ],
      ),
    );
    final tabController = useTabController(
      initialLength: 2,
      animationDuration: context.reduceMotion
          ? Duration.zero
          : kTabScrollDuration,
      keys: [context.reduceMotion],
    );
    useListenable(tabController);
    final onDeviceTab = tabController.index == 1;
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();
    final tabBar = TabBar(
      controller: tabController,
      // Fill aligns the underline with each tab; the global center alignment serves scrollable categories.
      tabAlignment: TabAlignment.fill,
      tabs: [
        Tab(text: context.l10n.downloadsServerTab),
        Tab(text: context.l10n.downloadsOnDeviceTab),
      ],
    );
    // The shell hosts desktop actions and search; tabs remain in the page body.
    final topBar = showsMergedTopBar(context);
    final search = DesktopSearchField(
      query: ref.watch(unifiedSearchQueryProvider),
      onChanged: (value) =>
          ref.read(unifiedSearchQueryProvider.notifier).state = value,
      onNavigate: () =>
          ref.read(unifiedSearchQueryProvider.notifier).state = '',
    );
    final actions = <Widget>[
      if (phone && !persistentBox)
        const PhoneSearchEntry(origin: PhoneSearchOrigin.plain),
      if (!onDeviceTab && erroredChapterIds.isNotEmpty)
        IconButton(
          tooltip: context.l10n.retryAll,
          onPressed: () async {
            final toast = ref.read(toastProvider);
            final repo = ref.read(downloadsRepositoryProvider);
            final result = await AsyncValue.guard(() async {
              for (final id in erroredChapterIds) {
                await repo.removeChapterFromDownloadQueue(id);
              }
              await repo.addChaptersBatchToDownloadQueue(erroredChapterIds);
            });
            result.showToastOnError(toast);
          },
          icon: const Icon(Icons.replay_rounded),
        ),
      if (!onDeviceTab && (downloadsChapterIds).isNotBlank)
        IconButton(
          onPressed: !canDownload
              ? null
              : () async {
                  if (!await confirmAction(
                        context,
                        title: context.l10n.confirmClearQueueTitle,
                        message: context.l10n.confirmClearQueueMessage,
                        action: context.l10n.confirmClearQueueTitle,
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  await AppUtils.guard(
                  ref.read(downloadsMapProvider.notifier).clearAll,
                  ref.read(toastProvider),
                  );
                },
          tooltip: canDownload ? null : context.l10n.accountPermissionDenied,
          icon: const Icon(Icons.delete_sweep_rounded),
        ),
    ];
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              title: context.usesDesktopShell
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: search,
                      ),
                    )
                  : Text(context.l10n.downloads),
              bottom: persistentBox
                  ? PhoneSearchBoxBottom(
                      origin: PhoneSearchOrigin.plain,
                      below: tabBar,
                    )
                  : tabBar,
              actions: actions,
      ),
      // Unknown run state offers Resume: starting an already-running downloader is a no-op.
      floatingActionButton: onDeviceTab
          ? const OfflineDownloadsFab()
          : (showDownloadsFAB
                ? DownloadsFab(
                    status: downloaderRunState ?? DownloaderState.STOPPED,
                  )
                : null),
      // Desktop has no page app bar to host these tabs.
      body: topBar
          ? Column(
              children: [
                tabBar,
                Expanded(
                  child: TabBarView(
                    controller: tabController,
                    children: [
                      _ServerDownloads(
                        downloadsChapterIds: downloadsChapterIds,
                        queueStatus: queueStatus,
                      ),
                      const OfflineFilesView(),
                    ],
                  ),
                ),
              ],
            )
          : TabBarView(
              controller: tabController,
              children: [
                _ServerDownloads(
                  downloadsChapterIds: downloadsChapterIds,
                  queueStatus: queueStatus,
                ),
                const OfflineFilesView(),
              ],
            ),
    );
    return topBar
        ? TopBarSlot(
            content: desktopSearchSlotContent(search: search, actions: actions),
            minWidth: searchTopBarSlotMinWidth(actions.length),
            child: scaffold,
          )
        : scaffold;
  }
}

class OfflineDownloadsFab extends ConsumerWidget {
  const OfflineDownloadsFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final hasPending = ref.watch(offlineHasPendingProvider).value ?? false;
    final paused = ref.watch(offlineDownloadsPausedProvider) ?? false;
    // Hide idle queues, including paused queues with no pending work.
    if (!hasPending) return const SizedBox.shrink();
    return FloatingActionButton.extended(
      icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
      label: Text(paused ? context.l10n.resume : context.l10n.pause),
      tooltip: !canDownload && paused
          ? context.l10n.accountPermissionDenied
          : null,
      onPressed: !canDownload && paused
          ? null
          : () => setOfflineDownloadsPaused(ref, !paused),
    );
  }
}

class _ServerDownloads extends ConsumerWidget {
  const _ServerDownloads({
    required this.downloadsChapterIds,
    required this.queueStatus,
  });

  final List<int> downloadsChapterIds;

  /// Use the queue query because mass enqueue can silence the live feed for minutes.
  final AsyncValue<DownloadStatusDto?> queueStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final toast = ref.watch(toastProvider);
    // The status query remains authoritative when the live socket is not
    // available on an otherwise-working LAN route.
    ref.watch(downloadUpdatesProvider);
    return queueStatus.showUiWhenData(
      context,
      (data) {
        if (data == null) {
          return Emoticons(title: context.l10n.errorSomethingWentWrong);
        } else if (downloadsChapterIds.isBlank) {
          return Emoticons(title: context.l10n.noDownloads);
        } else {
          final downloadsCount = (downloadsChapterIds.length)
              .getValueOnNullOrNegative();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(downloadStatusProvider.future),
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 88),
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!canDownload)
                    ListTile(
                      subtitle: Text(context.l10n.accountPermissionDenied),
                    ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.download_rounded),
                    title: Text(context.l10n.downloadsQueue),
                    trailing: Text("$downloadsCount"),
                  ),
                  const Divider(height: 1),
                ],
              ),
              onReorderItem: !canDownload
                  ? (_, _) {}
                  : (oldIndex, newIndex) => ref
                        .read(downloadsMapProvider.notifier)
                        .reorder(downloadsChapterIds[oldIndex], newIndex),
              itemBuilder: (context, index) {
                final chapterId = downloadsChapterIds[index];
                return DownloadProgressListTile(
                  key: ValueKey("$chapterId"),
                  index: index,
                  downloadsCount: downloadsCount,
                  chapterId: chapterId,
                  toast: toast,
                );
              },
              itemCount: downloadsCount,
            ),
          );
        }
      },
      refresh: () {
        ref.invalidate(downloadStatusProvider);
        ref.invalidate(downloadUpdatesProvider);
      },
      showGenericError: true,
    );
  }
}
