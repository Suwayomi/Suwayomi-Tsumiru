import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../widgets/emoticons.dart';
import '../../../../../widgets/fluent_expansion_tile.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../account/domain/account_access.dart';
import '../../../domain/downloads_queue/downloads_queue_model.dart';
import '../controller/downloads_controller.dart';
import 'download_progress_list_tile.dart';
import 'only_my_downloads.dart';

class ServerDownloadsBody extends ConsumerWidget {
  const ServerDownloadsBody({
    super.key,
    required this.downloadsChapterIds,
    required this.queueStatus,
    required this.toast,
  });

  final List<int> downloadsChapterIds;

  /// Use the queue query because mass enqueue can silence the live feed for minutes.
  final AsyncValue<DownloadStatusDto?> queueStatus;

  final Toast? toast;

  Widget _header(
    BuildContext context,
    bool canDownload,
    bool manageAll,
    int downloadsCount,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!canDownload)
        ListTile(subtitle: Text(context.l10n.accountPermissionDenied)),
      ListTile(
        dense: true,
        leading: const Icon(FluentIcons.arrow_download_24_regular),
        title: Text(context.l10n.downloadsQueue),
        trailing: Text("$downloadsCount"),
      ),
      if (manageAll) const OnlyMyDownloadsTile(),
    ],
  );

  Widget _queueTile(
    int chapterId,
    int index,
    int downloadsCount,
  ) => DownloadProgressListTile(
    key: ValueKey("$chapterId"),
    index: index,
    downloadsCount: downloadsCount,
    chapterId: chapterId,
    toast: toast,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(settledAccountAccessProvider);
    final canDownload = access.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final onlyMine = ref.watch(onlyMyDownloadsProvider).ifNull();
    final inLibrary = [
      for (final id in downloadsChapterIds)
        ref.watch(downloadsFromIdProvider(id))?.manga.user.inLibrary ?? true,
    ];
    // Single-user servers have no accounts to tell apart; they manage everything.
    final manageAll =
        access.canManageUsers ||
        access.capability == AccountCapability.unsupported;
    final mineIds = [
      for (var index = 0; index < downloadsChapterIds.length; index++)
        if (inLibrary[index]) downloadsChapterIds[index],
    ];
    final foreignIds = [
      for (var index = 0; index < downloadsChapterIds.length; index++)
        if (!inLibrary[index]) downloadsChapterIds[index],
    ];
    final grouped = (!manageAll || onlyMine) && foreignIds.isNotBlank;
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
          Future<void> onRefresh() => ref.refresh(downloadStatusProvider.future);
          if (!grouped) {
            return RefreshIndicator(
              onRefresh: onRefresh,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 88),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, canDownload, manageAll, downloadsCount),
                    const Divider(height: 1),
                  ],
                ),
                onReorderItem: !canDownload
                    ? (_, _) {}
                    : (oldIndex, newIndex) => ref
                          .read(downloadsMapProvider.notifier)
                          .reorder(downloadsChapterIds[oldIndex], newIndex),
                itemBuilder: (context, index) => _queueTile(
                  downloadsChapterIds[index],
                  index,
                  downloadsCount,
                ),
                itemCount: downloadsCount,
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 88),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, canDownload, manageAll, downloadsCount),
                  const Divider(height: 1),
                  ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorderItem: !canDownload
                        ? (_, _) {}
                        : (oldIndex, newIndex) {
                            final target = newIndex >= mineIds.length
                                ? downloadsChapterIds.length
                                : downloadsChapterIds.indexOf(
                                    mineIds[newIndex],
                                  );
                            ref
                                .read(downloadsMapProvider.notifier)
                                .reorder(mineIds[oldIndex], target);
                          },
                    itemBuilder: (context, index) =>
                        _queueTile(mineIds[index], index, downloadsCount),
                    itemCount: mineIds.length,
                  ),
                  FluentExpansionTile(
                    title: Text(
                      '${context.l10n.notInYourLibrary} (${foreignIds.length})',
                    ),
                    children: [
                      for (var index = 0; index < foreignIds.length; index++)
                        _queueTile(foreignIds[index], index, downloadsCount),
                    ],
                  ),
                ],
              ),
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
