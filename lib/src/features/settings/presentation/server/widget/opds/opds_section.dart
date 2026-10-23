import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/misc/app_utils.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/motion/reduce_motion.dart';
import '../../../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../../../widgets/popup_widgets/pop_button.dart';
import '../../../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../../../widgets/section_title.dart';
import '../../../../../account/data/account_providers.dart';
import '../../../../search/settings_search_registry.dart';
import 'data/opds_repository.dart';

String _sortOrderLabel(BuildContext context, Enum$SortOrder value) =>
    switch (value) {
      Enum$SortOrder.ASC => context.l10n.opdsSortAscending,
      Enum$SortOrder.DESC => context.l10n.opdsSortDescending,
      _ => value.name,
    };

String _cbzMimetypeLabel(BuildContext context, Enum$CbzMediaType value) =>
    switch (value) {
      Enum$CbzMediaType.LEGACY => context.l10n.opdsCbzLegacy,
      Enum$CbzMediaType.MODERN => context.l10n.opdsCbzModern,
      Enum$CbzMediaType.COMPATIBLE => context.l10n.opdsCbzCompatible,
      _ => value.name,
    };

/// Radio dialog with the setting's description above the options, matching
/// how WebUI's select shows its dialog description.
Future<void> _pickOpds<T>(
  BuildContext context, {
  required String title,
  required String description,
  required T value,
  required List<T> options,
  required String Function(T) name,
  required Future<void> Function(T) write,
}) async {
  final selected = await showDialog<T>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const Gap(16),
          RadioList<T>(
            optionList: options,
            value: value,
            getTitle: name,
            onChange: (option) => Navigator.pop(dialogContext, option),
          ),
        ],
      ),
      actions: const [PopButton()],
    ),
    animationStyle: context.motionStyle,
  );
  if (selected != null && selected != value) await write(selected);
}

class OpdsSection extends ConsumerWidget {
  const OpdsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final repository = ref.watch(opdsSettingsRepositoryProvider);
    final settings = ref.watch(opdsSettingsProvider);
    if (settings.hasError) return const SizedBox.shrink();
    final data = settings.value;
    if (data == null) return const SizedBox.shrink();
    Future<void> save(Future<bool> Function() action) async {
      final result = await AppUtils.guard(action, ref.read(toastProvider));
      if (result != null && context.mounted) {
        ref.invalidate(opdsSettingsProvider);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: context.l10n.opds),
        SettingsHighlightTarget(
          id: 'opdsBinaryFileSize',
          child: SettingsPropTile(
            title: context.l10n.opdsBinaryFileSize,
            description: context.l10n.opdsBinaryFileSizeDescription,
            type: SettingsPropType.switchTile(
              value: data.useBinaryFileSizes,
              onChanged: canManage
                  ? (value) => save(
                      () => repository.updateUseBinaryFileSizes(value),
                    )
                  : null,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'opdsItemsPerPage',
          // Explicit boundary: without it the engine folds this row into a
          // neighbouring switch row, the same merge webview_section.dart
          // guards against.
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: SettingsPropTile(
              title: context.l10n.opdsItemsPerPage,
              subtitle: data.itemsPerPage.toString(),
              description: context.l10n.opdsItemsPerPageDescription,
              type: SettingsPropType.numberSlider(
                min: 10,
                max: 5000,
                value: data.itemsPerPage.clamp(10, 5000),
                onChanged: canManage
                    ? (value) =>
                          save(() => repository.updateItemsPerPage(value))
                    : null,
              ),
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'opdsEnablePageReadProgress',
          child: SettingsPropTile(
            title: context.l10n.opdsEnablePageReadProgress,
            description: context.l10n.opdsEnablePageReadProgressDescription,
            type: SettingsPropType.switchTile(
              value: data.enablePageReadProgress,
              onChanged: canManage
                  ? (value) => save(
                      () => repository.updateEnablePageReadProgress(value),
                    )
                  : null,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'opdsMarkAsReadOnDownload',
          child: SettingsPropTile(
            title: context.l10n.opdsMarkAsReadOnDownload,
            description: context.l10n.opdsMarkAsReadOnDownloadDescription,
            type: SettingsPropType.switchTile(
              value: data.markAsReadOnDownload,
              onChanged: canManage
                  ? (value) => save(
                      () => repository.updateMarkAsReadOnDownload(value),
                    )
                  : null,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'opdsShowOnlyUnreadChapters',
          child: SettingsPropTile(
            title: context.l10n.opdsShowOnlyUnreadChapters,
            description: context.l10n.opdsShowOnlyUnreadChaptersDescription,
            type: SettingsPropType.switchTile(
              value: data.showOnlyUnreadChapters,
              onChanged: canManage
                  ? (value) => save(
                      () => repository.updateShowOnlyUnreadChapters(value),
                    )
                  : null,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'opdsShowOnlyDownloadedChapters',
          child: SettingsPropTile(
            title: context.l10n.opdsShowOnlyDownloadedChapters,
            description:
                context.l10n.opdsShowOnlyDownloadedChaptersDescription,
            type: SettingsPropType.switchTile(
              value: data.showOnlyDownloadedChapters,
              onChanged: canManage
                  ? (value) => save(
                      () => repository.updateShowOnlyDownloadedChapters(value),
                    )
                  : null,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'opdsSkipChapterMetadataFeed',
          child: SettingsPropTile(
            title: context.l10n.opdsSkipChapterMetadataFeed,
            description: context.l10n.opdsSkipChapterMetadataFeedDescription,
            type: SettingsPropType.switchTile(
              value: data.skipChapterMetadataFeed,
              onChanged: canManage
                  ? (value) => save(
                      () => repository.updateSkipChapterMetadataFeed(value),
                    )
                  : null,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'opdsChapterSortOrder',
          // Explicit boundary, same merge guard as above.
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: ListTile(
              title: Text(context.l10n.opdsChapterSortOrder),
              subtitle: Text(_sortOrderLabel(context, data.chapterSortOrder)),
              onTap: canManage
                  ? () => _pickOpds<Enum$SortOrder>(
                      context,
                      title: context.l10n.opdsChapterSortOrder,
                      description:
                          context.l10n.opdsChapterSortOrderDescription,
                      value: data.chapterSortOrder,
                      options: const [
                        Enum$SortOrder.ASC,
                        Enum$SortOrder.DESC,
                      ],
                      name: (value) => _sortOrderLabel(context, value),
                      write: (value) => save(
                        () => repository.updateChapterSortOrder(value),
                      ),
                    )
                  : null,
            ),
          ),
        ),
        SettingsHighlightTarget(
          id: 'opdsCbzMimetype',
          // Explicit boundary, same merge guard as above.
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: ListTile(
              title: Text(context.l10n.opdsCbzMimeType),
              subtitle: Text(_cbzMimetypeLabel(context, data.cbzMimetype)),
              onTap: canManage
                  ? () => _pickOpds<Enum$CbzMediaType>(
                      context,
                      title: context.l10n.opdsCbzMimeType,
                      description: context.l10n.opdsCbzMimeTypeDescription,
                      value: data.cbzMimetype,
                      options: const [
                        Enum$CbzMediaType.LEGACY,
                        Enum$CbzMediaType.MODERN,
                        Enum$CbzMediaType.COMPATIBLE,
                      ],
                      name: (value) => _cbzMimetypeLabel(context, value),
                      write: (value) =>
                          save(() => repository.updateCbzMimetype(value)),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
