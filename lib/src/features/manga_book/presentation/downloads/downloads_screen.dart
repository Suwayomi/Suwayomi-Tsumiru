// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/desktop/desktop_view_switch.dart';
import '../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../account/data/account_providers.dart';
import '../../../library/presentation/library/widgets/desktop_library_toolbar.dart';
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
import 'widgets/downloads_fab.dart';
import 'widgets/server_downloads_body.dart';

const _downloadsTextButtonChrome = 16.0 + 16.0 + 18.0 + 8.0;
const _downloadsFilledButtonChrome = 16.0 + 24.0 + 18.0 + 8.0;

// Compact controls first so the search retains its preferred width.
bool _downloadsToolbarIsCompact(
  BuildContext context,
  BoxConstraints constraints, {
  required bool showRetry,
  required bool showClear,
  required bool showToggle,
  required String retryLabel,
  required String clearLabel,
  required String toggleLabel,
}) {
  if (!constraints.hasBoundedWidth) return false;
  double textWidth(String value) => measureToolbarLabelWidth(context, value);

  final actionCount =
      (showRetry ? 1 : 0) + (showClear ? 1 : 0) + (showToggle ? 1 : 0);
  final neededBesidesSearch =
      2 * kDesktopToolbarSlotHPadding +
      actionCount * kDesktopTopBarGap +
      (showRetry ? _downloadsTextButtonChrome + textWidth(retryLabel) : 0.0) +
      (showClear ? _downloadsTextButtonChrome + textWidth(clearLabel) : 0.0) +
      (showToggle
          ? _downloadsFilledButtonChrome + textWidth(toggleLabel)
          : 0.0);
  return constraints.maxWidth - neededBesidesSearch < kDesktopSearchMaxWidth;
}

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
    final visibility = ref.watch(downloadsVisibilityProvider);
    final visibleIds = visibility.visibleIds;
    final visibleSet = visibleIds.toSet();
    final erroredChapterIds = ref.watch(
      downloadsMapProvider.select(
        (map) => [
          for (final d in map.values)
            if (d.state == DownloadState.ERROR) d.chapter.id,
        ],
      ),
    );
    final visibleErrored = [
      for (final id in erroredChapterIds)
        if (visibleSet.contains(id)) id,
    ];
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
    final desktop = context.usesDesktopShell;
    final tabBar = TabBar(
      controller: tabController,
      // Fill aligns the underline with each tab; the global center alignment serves scrollable categories.
      tabAlignment: TabAlignment.fill,
      tabs: [
        Tab(text: context.l10n.downloadsServerTab),
        Tab(text: context.l10n.downloadsOnDeviceTab),
      ],
    );
    final viewSwitch = DesktopViewSwitchBar(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      labels: [
        context.l10n.downloadsServerTab,
        context.l10n.downloadsOnDeviceTab,
      ],
      selectedIndex: tabController.index,
      onChanged: tabController.animateTo,
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
    Widget queueAction({
      required String label,
      required IconData icon,
      required VoidCallback? onPressed,
      String? tooltip,
      bool compact = false,
    }) => desktop && !compact
        ? Tooltip(
            message: tooltip ?? label,
            child: TextButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
          )
        : IconButton(
            tooltip: tooltip ?? label,
            onPressed: onPressed,
            icon: Icon(icon),
          );
    final showRetry = !onDeviceTab && visibleErrored.isNotEmpty;
    final showClear = !onDeviceTab && visibleIds.isNotBlank;
    final showToggle = desktop && !onDeviceTab && visibleIds.isNotEmpty;
    final toggleLabel = downloaderRunState == DownloaderState.STARTED
        ? context.l10n.pause
        : context.l10n.resume;
    final toggleIcon = downloaderRunState == DownloaderState.STARTED
        ? FluentIcons.pause_24_regular
        : FluentIcons.play_24_regular;
    Future<void> toggleDownloads() async {
      final repo = ref.read(downloadsRepositoryProvider);
      (await AsyncValue.guard(
        downloaderRunState == DownloaderState.STARTED
            ? repo.stopDownloads
            : repo.startDownloads,
      )).showToastOnError(ref.read(toastProvider));
    }

    List<Widget> buildActions({bool compact = false}) => <Widget>[
      if (phone && !persistentBox)
        const PhoneSearchEntry(origin: PhoneSearchOrigin.plain),
      if (showRetry)
        queueAction(
          label: context.l10n.retryAll,
          compact: compact,
          onPressed: () async {
            final toast = ref.read(toastProvider);
            final repo = ref.read(downloadsRepositoryProvider);
            final result = await AsyncValue.guard(() async {
              for (final id in visibleErrored) {
                await repo.removeChapterFromDownloadQueue(id);
              }
              await repo.addChaptersBatchToDownloadQueue(visibleErrored);
            });
            result.showToastOnError(toast);
          },
          icon: FluentIcons.replay_24_regular,
        ),
      if (showClear)
        queueAction(
          label: context.l10n.confirmClearQueueTitle,
          compact: compact,
          tooltip: canDownload ? null : context.l10n.accountPermissionDenied,
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
                  final clear = visibility.manageAll
                      ? ref.read(downloadsMapProvider.notifier).clearAll
                      : () => ref
                          .read(downloadsMapProvider.notifier)
                          .cancelQueuedChapters(visibleIds);
                  await AppUtils.guard(
                  clear,
                  ref.read(toastProvider),
                  );
                },
          icon: FluentIcons.delete_dismiss_24_regular,
        ),
      if (showToggle)
        compact
            ? Tooltip(
                message: toggleLabel,
                child: FilledButton(
                  onPressed: !canDownload ? null : toggleDownloads,
                  child: Icon(toggleIcon, size: 18),
                ),
              )
            : FilledButton.icon(
                onPressed: !canDownload ? null : toggleDownloads,
                icon: Icon(toggleIcon, size: 18),
                label: Text(toggleLabel),
              ),
    ];
    final actions = buildActions();
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              title: desktop
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: search,
                      ),
                    )
                  : Text(context.l10n.downloads),
              bottom: desktop
                  ? null
                  : persistentBox
                  ? PhoneSearchBoxBottom(
                      origin: PhoneSearchOrigin.plain,
                      below: tabBar,
                    )
                  : tabBar,
              actions: actions,
      ),
      // Unknown run state offers Resume: starting an already-running downloader is a no-op.
      floatingActionButton: desktop && !onDeviceTab
          ? null
          : onDeviceTab
          ? const OfflineDownloadsFab()
          : (showDownloadsFAB &&
                  (visibility.manageAll || visibleIds.isNotBlank)
                ? DownloadsFab(
                    status: downloaderRunState ?? DownloaderState.STOPPED,
                  )
                : null),
      // Desktop has no page app bar to host these tabs.
      body: topBar || desktop
          ? Column(
              children: [
                if (desktop) viewSwitch else tabBar,
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
            content: LayoutBuilder(
              builder: (context, constraints) {
                final compact = _downloadsToolbarIsCompact(
                  context,
                  constraints,
                  showRetry: showRetry,
                  showClear: showClear,
                  showToggle: showToggle,
                  retryLabel: context.l10n.retryAll,
                  clearLabel: context.l10n.confirmClearQueueTitle,
                  toggleLabel: toggleLabel,
                );
                return desktopSearchSlotContent(
                  search: search,
                  actions: buildActions(compact: compact),
                );
              },
            ),
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
      icon: Icon(paused ? FluentIcons.play_24_regular : FluentIcons.pause_24_regular),
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
    // The status query remains authoritative when the live socket is not
    // available on an otherwise-working LAN route.
    ref.watch(downloadUpdatesProvider);
    return ServerDownloadsBody(
      downloadsChapterIds: downloadsChapterIds,
      queueStatus: queueStatus,
      toast: ref.watch(toastProvider),
    );
  }
}
