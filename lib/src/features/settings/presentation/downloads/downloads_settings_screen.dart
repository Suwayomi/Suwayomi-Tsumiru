import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../widgets/section_title.dart';
import '../../controller/server_controller.dart';
import '../../domain/settings/settings.dart';
import 'data/delete_chapters_settings_repository.dart';
import 'data/downloads_settings_repository.dart';

/// Labels for the "delete while reading" select (0 = disabled, N = the Nth
/// chapter behind), matching the Suwayomi-WebUI wording.
String _deleteWhileReadingLabel(BuildContext context, int value) =>
    switch (value) {
      1 => context.l10n.deleteWhileReadingLastRead,
      2 => context.l10n.deleteWhileReadingSecondToLast,
      3 => context.l10n.deleteWhileReadingThirdToLast,
      4 => context.l10n.deleteWhileReadingFourthToLast,
      5 => context.l10n.deleteWhileReadingFifthToLast,
      _ => context.l10n.deleteWhileReadingDisabled,
    };

class DownloadsSettingsScreen extends ConsumerWidget {
  const DownloadsSettingsScreen({super.key});

  @override
  Widget build(context, ref) {
    final repository = ref.watch(downloadsSettingsRepositoryProvider);
    final serverSettings = ref.watch(settingsProvider);
    final deleteSettings =
        ref.watch(deleteChaptersSettingsControllerProvider).valueOrNull ??
            const DeleteChaptersSettings();
    final deleteController =
        ref.read(deleteChaptersSettingsControllerProvider.notifier);
    return ListTileTheme(
      data: const ListTileThemeData(
        subtitleTextStyle: TextStyle(color: Colors.grey),
      ),
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.downloads)),
        body: RefreshIndicator(
          onRefresh: () => Future.wait([
            ref.refresh(settingsProvider.future),
            ref.refresh(deleteChaptersSettingsControllerProvider.future),
          ]),
          child: serverSettings.showUiWhenData(
            context,
            (data) {
              final DownloadsSettingsDto? downloadsSettingsDto = data;
              if (downloadsSettingsDto == null) {
                return Emoticons(
                  title: context.l10n.noPropFound(context.l10n.settings),
                );
              }
              return ListView(
                children: [
                  SectionTitle(title: context.l10n.general),
                  SettingsPropTile(
                    title: context.l10n.downloadLocation,
                    description: context.l10n.downloadLocationHint,
                    type: SettingsPropType.textField(
                      hintText:
                          context.l10n.enterProp(context.l10n.downloadLocation),
                      value: downloadsSettingsDto.downloadsPath,
                      onChanged: repository.updateDownloadsLocation,
                    ),
                    subtitle: downloadsSettingsDto.downloadsPath,
                  ),
                  SettingsPropTile(
                    title: context.l10n.saveAsCBZArchive,
                    type: SettingsPropType.switchTile(
                      value: downloadsSettingsDto.downloadAsCbz,
                      onChanged: repository.updateDownloadAsCbz,
                    ),
                  ),
                  SectionTitle(title: context.l10n.deleteChapters),
                  SettingsPropTile(
                    title:
                        context.l10n.deleteChapterAfterManuallyMarkedRead,
                    type: SettingsPropType.switchTile(
                      value: deleteSettings.deleteManuallyMarkedRead,
                      onChanged: deleteController.setDeleteManuallyMarkedRead,
                    ),
                  ),
                  ListTile(
                    title: Text(
                      context.l10n.deleteFinishedChaptersWhileReading,
                    ),
                    subtitle: Text(_deleteWhileReadingLabel(
                      context,
                      deleteSettings.deleteWhileReading,
                    )),
                    onTap: () => showDialog(
                      context: context,
                      builder: (context) => RadioListPopup<int>(
                        title:
                            context.l10n.deleteFinishedChaptersWhileReading,
                        optionList: const [0, 1, 2, 3, 4, 5],
                        getOptionTitle: (value) =>
                            _deleteWhileReadingLabel(context, value),
                        value: deleteSettings.deleteWhileReading,
                        onChange: (value) {
                          deleteController.setDeleteWhileReading(value);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
                  SettingsPropTile(
                    title: context.l10n.allowDeletingBookmarkedChapters,
                    type: SettingsPropType.switchTile(
                      value: deleteSettings.deleteWithBookmark,
                      onChanged: deleteController.setDeleteWithBookmark,
                    ),
                  ),
                  SectionTitle(title: context.l10n.autoDownload),
                  SettingsPropTile(
                    title: context.l10n.autoDownloadNewChapters,
                    type: SettingsPropType.switchTile(
                      value: downloadsSettingsDto.autoDownloadNewChapters,
                      onChanged: repository.toggleAutoDownloadNewChapters,
                    ),
                  ),
                  SettingsPropTile(
                    title: context.l10n.chapterDownloadLimit,
                    description: context.l10n.chapterDownloadLimitDesc,
                    type: SettingsPropType.numberSlider(
                      value: downloadsSettingsDto.autoDownloadNewChaptersLimit,
                      min: 0,
                      max: 20,
                      onChanged: repository.updateAutoDownloadNewChaptersLimit,
                    ),
                    subtitle: context.l10n.nChapters(
                        downloadsSettingsDto.autoDownloadNewChaptersLimit),
                  ),
                  SettingsPropTile(
                    title: context.l10n.excludeEntryWithUnreadChapters,
                    type: SettingsPropType.switchTile(
                      value:
                          downloadsSettingsDto.excludeEntryWithUnreadChapters,
                      onChanged:
                          repository.toggleExcludeEntryWithUnreadChapters,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
