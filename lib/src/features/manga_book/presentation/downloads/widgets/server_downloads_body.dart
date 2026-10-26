import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/app_utils.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../widgets/emoticons.dart';
import '../../../../../widgets/fluent_expansion_tile.dart';
import '../../../../../widgets/popup_widgets/confirm_action.dart';
import '../../../../../widgets/selection_action_bar.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../browse_center/presentation/source/controller/source_controller.dart';
import '../../../domain/downloads_queue/downloads_queue_model.dart';
import '../controller/downloads_controller.dart';
import 'download_progress_list_tile.dart';
import 'only_my_downloads.dart';

class ServerDownloadsBody extends HookConsumerWidget {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(settledAccountAccessProvider);
    final canDownload = access.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS);
    final onlyMine = ref.watch(onlyMyDownloadsProvider).ifNull();
    final visibility = ref.watch(downloadsVisibilityProvider);
    // Single-user servers have no accounts to tell apart; they manage everything.
    final manageAll = visibility.manageAll;
    final mineIds = visibility.mineIds;
    final mineSet = mineIds.toSet();
    final foreignIds = [
      for (final id in downloadsChapterIds)
        if (!mineSet.contains(id)) id,
    ];
    final grouped = manageAll && onlyMine && foreignIds.isNotBlank;
    final visibleIds = visibility.visibleIds;
    final desktop = context.usesDesktopShell;
    final map = desktop ? ref.watch(downloadsMapProvider) : null;
    final sources = desktop ? ref.watch(sourceListProvider).value : null;
    final selection = useState<Set<int>>({});
    final foreignExpanded = useState(false);
    final anchor = useRef<int?>(null);
    final selectableIds = grouped && !foreignExpanded.value
        ? mineIds
        : visibleIds;
    final liveIds = selectableIds.toSet();
    final selectedIds = selectableIds.where(selection.value.contains).toList();
    final selecting = selectedIds.isNotEmpty;
    final selectionFocus = useFocusNode();
    usePruneSelection(selection, liveIds, context);
    useEffect(() {
      if (selecting) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) selectionFocus.requestFocus();
        });
      }
      return null;
    }, [selecting]);
    final displayIds = <int>[];
    void clear() => selection.value = {};
    void toggle(int id) {
      final next = {...selection.value};
      if (desktop &&
          HardwareKeyboard.instance.isShiftPressed &&
          anchor.value != null &&
          displayIds.contains(anchor.value)) {
        final start = displayIds.indexOf(anchor.value!);
        final end = displayIds.indexOf(id);
        next.addAll(
          displayIds.sublist(
            start < end ? start : end,
            (start > end ? start : end) + 1,
          ),
        );
      } else {
        if (!next.add(id)) next.remove(id);
        anchor.value = id;
      }
      selection.value = next;
    }

    Widget queueTile(int id, int dragIndex) =>
        DownloadProgressListTile(
          key: ValueKey('$id'),
          chapterId: id,
          toast: toast,
          index: downloadsChapterIds.indexOf(id),
          dragIndex: dragIndex,
          downloadsCount: downloadsChapterIds.length,
          selecting: selecting,
          selected: selection.value.contains(id),
          onSelect: () => toggle(id),
          onTap: () {
            if (selecting ||
                (desktop && AppUtils.isMultiSelectPressed())) {
              toggle(id);
            } else {
              final mangaId = ref.read(downloadsFromIdProvider(id))?.manga.id;
              if (mangaId != null) MangaRoute(mangaId: mangaId).push(context);
            }
          },
        );
    final leading = <Widget>[
      IconButton(
        tooltip: context.l10n.cancel,
        onPressed: clear,
        icon: const Icon(Icons.close),
      ),
      Text(
        context.l10n.numSelected(selectedIds.length),
        style: context.textTheme.titleSmall,
      ),
    ];
    final actions = <Widget>[
      IconButton(
        tooltip: context.l10n.selectAll,
        icon: const Icon(Icons.select_all),
        onPressed: () => selection.value = liveIds,
      ),
      for (final toTop in [true, false])
        if (desktop)
          TextButton.icon(
            icon: Icon(
              toTop
                  ? FluentIcons.arrow_up_24_regular
                  : FluentIcons.arrow_down_24_regular,
            ),
            label: Text(
              toTop ? context.l10n.moveToTop : context.l10n.moveToBottom,
            ),
            onPressed: canDownload
                ? () => ref
                      .read(downloadsMapProvider.notifier)
                      .moveChapters(selectedIds, toTop: toTop)
                : null,
          )
        else
          IconButton(
            tooltip: toTop ? context.l10n.moveToTop : context.l10n.moveToBottom,
            icon: Icon(
              toTop
                  ? FluentIcons.arrow_up_24_regular
                  : FluentIcons.arrow_down_24_regular,
            ),
            onPressed: canDownload
                ? () => ref
                      .read(downloadsMapProvider.notifier)
                      .moveChapters(selectedIds, toTop: toTop)
                : null,
          ),
      TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: context.theme.colorScheme.error,
        ),
        icon: const Icon(Icons.close),
        label: Text(context.l10n.cancel),
        onPressed: !canDownload
            ? null
            : () async {
                if (selectedIds.length > 1) {
                  if (!await confirmAction(
                        context,
                        title: context.l10n.cancelDownloadsTitle(
                          selectedIds.length,
                        ),
                        message: context.l10n.cancelDownloadsMessage,
                        action: context.l10n.cancelDownloads,
                      ) ||
                      !context.mounted) {
                    return;
                  }
                }
                final message = context.l10n.stillRequestedByAnotherAccount;
                final result = await AsyncValue.guard(
                  () => ref
                      .read(downloadsMapProvider.notifier)
                      .cancelQueuedChapters(selectedIds),
                );
                result.showToastOnError(toast);
                if ((result.value ?? const <int>{}).isNotEmpty) {
                  toast?.show(message);
                }
                clear();
              },
      ),
    ];
    Map<String?, List<int>> groupBySource(List<int> ids) {
      final groups = <String?, List<int>>{};
      for (final id in ids) {
        groups.putIfAbsent(map?[id]?.manga.source?.id, () => []).add(id);
      }
      return groups;
    }

    Widget desktopGroups(List<int> ids) {
      final groups = groupBySource(ids);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Row(
                children: [
                  Text(
                    sources
                            ?.where((source) => source.id == group.key)
                            .firstOrNull
                            ?.name ??
                        context.l10n.unknownSource,
                    style: context.textTheme.titleSmall,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${group.value.length}',
                    style: TextStyle(
                      color: context.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ReorderableListView.builder(
              buildDefaultDragHandles: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: group.value.length,
              itemBuilder: (context, index) =>
                  queueTile(group.value[index], index),
              onReorderItem: !canDownload || selecting
                  ? (_, _) {}
                  : (oldIndex, newIndex) {
                      final target = newIndex >= group.value.length
                          ? downloadsChapterIds.length
                          : downloadsChapterIds.indexOf(group.value[newIndex]);
                      ref
                          .read(downloadsMapProvider.notifier)
                          .reorder(group.value[oldIndex], target);
                    },
            ),
          ],
        ],
      );
    }

    if (desktop) {
      for (final ids in [
        grouped ? mineIds : visibleIds,
        if (grouped && foreignExpanded.value) foreignIds,
      ]) {
        displayIds.addAll(
          groupBySource(ids).values.expand((group) => group),
        );
      }
    } else {
      displayIds.addAll(
        grouped
            ? [...mineIds, if (foreignExpanded.value) ...foreignIds]
            : visibleIds,
      );
    }
    final body = queueStatus.showUiWhenData(
      context,
      (data) {
        if (data == null) {
          return Emoticons(title: context.l10n.errorSomethingWentWrong);
        } else if (visibleIds.isBlank) {
          return Emoticons(title: context.l10n.noDownloads);
        } else {
          final downloadsCount = (manageAll
                  ? downloadsChapterIds.length
                  : visibleIds.length)
              .getValueOnNullOrNegative();
          Future<void> onRefresh() => ref.refresh(downloadStatusProvider.future);
          if (desktop) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: RefreshIndicator(
                  onRefresh: onRefresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!canDownload)
                          ListTile(
                            subtitle: Text(
                              context.l10n.accountPermissionDenied,
                            ),
                          ),
                        if (selecting)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [...leading, ...actions]),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  context.l10n.downloadsQueue,
                                  style: context.textTheme.titleMedium,
                                ),
                                const SizedBox(width: 8),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: context
                                        .theme
                                        .colorScheme
                                        .secondaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 1,
                                    ),
                                    child: Text(
                                      '$downloadsCount',
                                      style: context.textTheme.labelSmall,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (manageAll) const OnlyMyDownloadsTile(),
                        desktopGroups(grouped ? mineIds : visibleIds),
                        if (grouped)
                          FluentExpansionTile(
                            initiallyExpanded: foreignExpanded.value,
                            onExpansionChanged: (expanded) =>
                                foreignExpanded.value = expanded,
                            title: Text(
                              '${context.l10n.notInYourLibrary} (${foreignIds.length})',
                            ),
                            children: [desktopGroups(foreignIds)],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
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
                    : (oldIndex, newIndex) {
                        if (manageAll) {
                          ref
                              .read(downloadsMapProvider.notifier)
                              .reorder(visibleIds[oldIndex], newIndex);
                          return;
                        }
                        final target = newIndex >= visibleIds.length
                            ? downloadsChapterIds.length
                            : downloadsChapterIds.indexOf(
                                visibleIds[newIndex],
                              );
                        ref
                            .read(downloadsMapProvider.notifier)
                            .reorder(visibleIds[oldIndex], target);
                      },
                itemBuilder: (context, index) =>
                    queueTile(visibleIds[index], index),
                itemCount: visibleIds.length,
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
                        queueTile(mineIds[index], index),
                    itemCount: mineIds.length,
                  ),
                  FluentExpansionTile(
                    initiallyExpanded: foreignExpanded.value,
                    onExpansionChanged: (expanded) =>
                        foreignExpanded.value = expanded,
                    title: Text(
                      '${context.l10n.notInYourLibrary} (${foreignIds.length})',
                    ),
                    children: [
                      for (var index = 0; index < foreignIds.length; index++)
                        queueTile(foreignIds[index], index),
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
    final content = Stack(
      children: [
        body,
        if (selecting && !desktop)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SelectionActionBar(leading: leading, actions: actions),
          ),
      ],
    );
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) clear();
      },
      child: CallbackShortcuts(
        bindings: selecting
            ? {const SingleActivator(LogicalKeyboardKey.escape): clear}
            : const {},
        child: Focus(focusNode: selectionFocus, child: content),
      ),
    );
  }
}
