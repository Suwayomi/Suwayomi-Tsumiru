import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';

import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../widgets/section_title.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../account/data/account_providers.dart';
import '../../../library/domain/category/category_model.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../offline/presentation/offline_settings_screen.dart';
import '../../controller/server_controller.dart';
import '../../data/user_settings.dart';
import '../../domain/settings/settings.dart';
import '../../search/settings_search_registry.dart';
import 'data/delete_chapters_settings_repository.dart';
import 'data/downloads_settings_repository.dart';
import 'widgets/auto_download_categories_dialog.dart';

/// Labels for the "after reading automatically delete" select (0 = disabled,
/// N = the Nth chapter behind), matching the Suwayomi-WebUI wording.
String _deleteWhileReadingLabel(BuildContext context, int value) =>
    switch (value) {
      1 => context.l10n.deleteWhileReadingLastRead,
      2 => context.l10n.deleteWhileReadingSecondToLast,
      3 => context.l10n.deleteWhileReadingThirdToLast,
      4 => context.l10n.deleteWhileReadingFourthToLast,
      5 => context.l10n.deleteWhileReadingFifthToLast,
      _ => context.l10n.deleteWhileReadingDisabled,
    };

/// One "Delete chapters" section (used for both the on-device and the server
/// copies — identical controls, different backing settings).
///
/// [whileReadingSubOptions] renders directly below the "delete finished
/// chapters while reading" row — the option that controls whether they're
/// meaningful at all — rather than at the end of the section, so a
/// dependent toggle stays visually attached to what governs it.
///
/// [targetIdPrefix] namespaces the three rows' highlight ids per tab
/// ('server' / 'device'): the two tabs share titles but never target ids,
/// so search can scroll to the right tab's row.
List<Widget> _deleteSection(
  BuildContext context, {
  required String title,
  required String description,
  required DeleteChaptersSettings settings,
  required Future<void> Function(bool) onManual,
  required void Function(int) onWhileReading,
  required Future<void> Function(bool) onBookmark,
  required String targetIdPrefix,
  List<Widget> whileReadingSubOptions = const [],
}) => [
  SectionTitle(title: title),
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Text(
      description,
      style: context.textTheme.bodySmall?.copyWith(
        color: context.theme.hintColor,
      ),
    ),
  ),
  SettingsHighlightTarget(
    id: '${targetIdPrefix}DeleteManuallyMarkedRead',
    child: SettingsPropTile(
      title: context.l10n.deleteChapterAfterManuallyMarkedRead,
      type: SettingsPropType.switchTile(
        value: settings.deleteManuallyMarkedRead,
        onChanged: onManual,
      ),
    ),
  ),
  SettingsHighlightTarget(
    id: '${targetIdPrefix}DeleteWhileReading',
    child: ListTile(
      title: Text(context.l10n.deleteFinishedChaptersWhileReading),
      subtitle: Text(
        _deleteWhileReadingLabel(context, settings.deleteWhileReading),
      ),
      onTap: () => showDialog(
        context: context,
        builder: (context) => RadioListPopup<int>(
          title: context.l10n.deleteFinishedChaptersWhileReading,
          optionList: const [0, 1, 2, 3, 4, 5],
          getOptionTitle: (value) => _deleteWhileReadingLabel(context, value),
          value: settings.deleteWhileReading,
          onChange: (value) {
            onWhileReading(value);
            if (context.mounted) Navigator.pop(context);
          },
        ),
        animationStyle: context.motionStyle,
      ),
    ),
  ),
  ...whileReadingSubOptions,
  SettingsHighlightTarget(
    id: '${targetIdPrefix}DeleteWithBookmark',
    child: SettingsPropTile(
      title: context.l10n.allowDeletingBookmarkedChapters,
      type: SettingsPropType.switchTile(
        value: settings.deleteWithBookmark,
        onChanged: onBookmark,
      ),
    ),
  ),
];

/// Indented dependent toggle, shown only while its controlling option makes
/// it meaningful — same treatment as the reader settings' sub-toggles (see
/// `_SubSwitchTile` in reading_mode_tab.dart / general_tab.dart), so a
/// dependent option doesn't read as a normal, independent one.
class _SubSwitchTile extends StatelessWidget {
  const _SubSwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 16),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Downloads settings, split into two tabs:
///   * Server — what the Suwayomi server downloads from sources.
///   * On-device — copies kept on this phone (Wi-Fi-only, storage, deletion).
///
/// [initialTab] selects the tab the page opens on (0 Server, 1 On device).
/// Search entries carry it as `tabIndex` and the route as the `tab` query
/// value, so opening a result lands on the tab its row lives on before the
/// highlight seeks. Out-of-range values fall back to Server.
class DownloadsSettingsScreen extends StatelessWidget {
  const DownloadsSettingsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    // Native desktop draws the toolbar in the shell bar instead of an app
    // bar; the tabs stay in the page body.
    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.downloads);
    final tabBar = TabBar(
      tabs: [
        Tab(text: context.l10n.downloadsServerTab),
        Tab(text: context.l10n.downloadsOnDeviceTab),
      ],
    );
    final content = DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      animationDuration: context.reduceMotion
          ? Duration.zero
          : kTabScrollDuration,
      child: ListTileTheme(
        data: ListTileThemeData(
          subtitleTextStyle: TextStyle(
            color: context.theme.colorScheme.onSurfaceVariant,
          ),
        ),
        child: Scaffold(
          appBar: topBar
              ? null
              : AppBar(
                  title: title,
                  bottom: tabBar,
                ),
          body: topBar
              ? Column(
                  children: [
                    tabBar,
                    const Expanded(
                      child: TabBarView(
                        children: [
                          _ServerDownloadsTab(),
                          _OnDeviceDownloadsTab(),
                        ],
                      ),
                    ),
                  ],
                )
              : const TabBarView(
                  children: [_ServerDownloadsTab(), _OnDeviceDownloadsTab()],
                ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: content,
    );
  }
}

/// Server-side downloads: where/how the server stores chapters, auto-download,
/// and the server copy's delete rules.
class _ServerDownloadsTab extends ConsumerWidget {
  const _ServerDownloadsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(downloadsSettingsRepositoryProvider);
    final serverSettings = ref.watch(settingsProvider);
    final personalSettings = ref.watch(personalSettingsProvider);
    final access = ref.watch(settledAccountAccessProvider);
    final canManage = access.allows(Enum$UserPermission.MANAGE_SETTINGS);
    final personalState = ref.watch(personalSettingsStateProvider);
    final canEditPersonal = personalState == PersonalSettingsState.ready;
    final serverDelete =
        ref.watch(deleteChaptersSettingsControllerProvider).value ??
        const DeleteChaptersSettings();
    final serverDeleteController = ref.read(
      deleteChaptersSettingsControllerProvider.notifier,
    );
    final categories =
        ref.watch(categoryControllerProvider).value ?? const <CategoryDto>[];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(userSettingsProvider);
        ref.invalidate(settingsProvider);
        await ref.read(settingsProvider.future);
      },
      child: serverSettings.showUiWhenData(context, (data) {
        final DownloadsSettingsDto? downloadsSettingsDto = canEditPersonal
            ? personalSettings.value
            : data;
        if (downloadsSettingsDto == null) {
          return Emoticons(
            title: context.l10n.noPropFound(context.l10n.settings),
          );
        }
        // Permission/personal gates only disable these rows (onChanged null);
        // they stay mounted, so every Server entry is always visible.
        return SettingsHighlightScope(
          child: ListView(
            children: [
              SectionTitle(title: context.l10n.general),
              SettingsHighlightTarget(
                id: 'downloadLocation',
                child: SettingsPropTile(
                  title: context.l10n.downloadLocation,
                  description: context.l10n.downloadLocationHint,
                  type: SettingsPropType.textField(
                    hintText: context.l10n.enterProp(
                      context.l10n.downloadLocation,
                    ),
                    value: downloadsSettingsDto.downloadsPath,
                    onChanged: canManage
                        ? repository.updateDownloadsLocation
                        : null,
                  ),
                  subtitle: !canManage
                      ? context.l10n.manageSettingsPermissionRequired
                      : downloadsSettingsDto.downloadsPath.isNotBlank
                      ? downloadsSettingsDto.downloadsPath
                      : context.l10n.defaultFolderPath,
                ),
              ),
              SettingsHighlightTarget(
                id: 'saveAsCbz',
                child: SettingsPropTile(
                  title: context.l10n.saveAsCBZArchive,
                  subtitle: canManage
                      ? null
                      : context.l10n.manageSettingsPermissionRequired,
                  type: SettingsPropType.switchTile(
                    value: downloadsSettingsDto.downloadAsCbz,
                    onChanged: canManage
                        ? repository.updateDownloadAsCbz
                        : null,
                  ),
                ),
              ),
              // Server downloads (shared with the web interface). Default off.
              ..._deleteSection(
                context,
                title: context.l10n.deleteServerDownloads,
                description: context.l10n.deleteServerDownloadsDescription,
                settings: serverDelete,
                onManual: serverDeleteController.setDeleteManuallyMarkedRead,
                onWhileReading: serverDeleteController.setDeleteWhileReading,
                onBookmark: serverDeleteController.setDeleteWithBookmark,
                targetIdPrefix: 'server',
              ),
              SectionTitle(title: context.l10n.autoDownload),
              if (personalState == PersonalSettingsState.unavailable)
                ListTile(title: Text(context.l10n.accountSettingsUnavailable)),
              SettingsHighlightTarget(
                id: 'autoDownloadNewChapters',
                child: SettingsPropTile(
                  title: context.l10n.autoDownloadNewChapters,
                  type: SettingsPropType.switchTile(
                    value: downloadsSettingsDto.autoDownloadNewChapters,
                    onChanged: canEditPersonal
                        ? repository.toggleAutoDownloadNewChapters
                        : null,
                  ),
                ),
              ),
              SettingsHighlightTarget(
                id: 'chapterDownloadLimit',
                child: SettingsPropTile(
                  title: context.l10n.chapterDownloadLimit,
                  description: context.l10n.chapterDownloadLimitDesc,
                  type: SettingsPropType.numberSlider(
                    value: downloadsSettingsDto.autoDownloadNewChaptersLimit,
                    min: 0,
                    max: 20,
                    onChanged: canEditPersonal
                        ? repository.updateAutoDownloadNewChaptersLimit
                        : null,
                  ),
                  subtitle: context.l10n.nChapters(
                    downloadsSettingsDto.autoDownloadNewChaptersLimit,
                  ),
                ),
              ),
              SettingsHighlightTarget(
                id: 'excludeEntryWithUnreadChapters',
                child: SettingsPropTile(
                  title: context.l10n.excludeEntryWithUnreadChapters,
                  type: SettingsPropType.switchTile(
                    value: downloadsSettingsDto.excludeEntryWithUnreadChapters,
                    onChanged: canEditPersonal
                        ? repository.toggleExcludeEntryWithUnreadChapters
                        : null,
                  ),
                ),
              ),
              // Greyed while auto-download is off, never unmounted.
              SettingsHighlightTarget(
                id: 'autoDownloadCategories',
                child: ListTile(
                  enabled: downloadsSettingsDto.autoDownloadNewChapters,
                  title: Text(context.l10n.autoDownloadCategories),
                  subtitle: Text(
                    autoDownloadCategoriesSummary(context, categories),
                  ),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AutoDownloadCategoriesDialog(),
                    animationStyle: context.motionStyle,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// On-device downloads: this phone's copies — the on-device delete rules plus
/// Wi-Fi-only, concurrency, and storage management.
class _OnDeviceDownloadsTab extends ConsumerWidget {
  const _OnDeviceDownloadsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localDelete = ref.watch(localDeleteSettingsProvider);
    return SettingsHighlightScope(
      child: ListView(
        children: [
          // On-device downloads (this phone). Independent, default off.
          ..._deleteSection(
            context,
            title: context.l10n.deleteOnDeviceDownloads,
            description: context.l10n.deleteOnDeviceDownloadsDescription,
            settings: localDelete,
            onManual: (v) async => ref
                .read(localDeleteManuallyMarkedReadProvider.notifier)
                .update(v),
            onWhileReading: (v) =>
                ref.read(localDeleteWhileReadingProvider.notifier).update(v),
            onBookmark: (v) async =>
                ref.read(localDeleteWithBookmarkProvider.notifier).update(v),
            targetIdPrefix: 'device',
            // Only meaningful when the keep window has at least 1 protected
            // slot — rendered right under the option that controls it.
            whileReadingSubOptions: localDelete.deleteWhileReading >= 2
                ? [
                    SettingsHighlightTarget(
                      id: 'downloadProtectionWindow',
                      child: _SubSwitchTile(
                        title: context.l10n.downloadProtectionWindowTitle,
                        subtitle:
                            context.l10n.downloadProtectionWindowDescription,
                        value:
                            ref.watch(localDownloadProtectionWindowProvider) ??
                            false,
                        onChanged: (v) async => ref
                            .read(
                              localDownloadProtectionWindowProvider.notifier,
                            )
                            .update(v),
                      ),
                    ),
                  ]
                : const [],
          ),
          ...buildOnDeviceStorageTiles(context, ref),
        ],
      ),
    );
  }
}
