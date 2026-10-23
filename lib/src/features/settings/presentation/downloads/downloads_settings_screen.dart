import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';

import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../account/data/account_providers.dart';
import '../../../library/domain/category/category_model.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../offline/presentation/offline_settings_screen.dart';
import '../../controller/server_controller.dart';
import '../../data/user_settings.dart';
import '../../domain/settings/settings.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import 'data/delete_chapters_settings_repository.dart';
import 'data/downloads_settings_repository.dart';
import 'widgets/auto_download_categories_dialog.dart';

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
                  leading: detailNavigationBackButton(context),
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
        ref.invalidate(autoDownloadIgnoreReUploadsProvider);
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
          child: Center(
            child: ConstrainedBox(
              constraints: settingsPageConstraints(context),
              child: ListView(
                padding: settingsPagePadding(context),
                children: [
                  SettingsGroupHeading(
                    label: context.l10n.general,
                    first: true,
                  ),
                  SettingsGroupCard(
                    children: [
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
                    ],
                  ),
                  // Image download processing lives on Server › Images
                  // only now; the same editor used to be linked from here too.
                  // Server downloads (shared with the web interface).
                  // Default off.
                  ...deleteChaptersSection(
                    context,
                    title: context.l10n.deleteServerDownloads,
                    description: context.l10n.deleteServerDownloadsDescription,
                    settings: serverDelete,
                    onManual:
                        serverDeleteController.setDeleteManuallyMarkedRead,
                    onWhileReading:
                        serverDeleteController.setDeleteWhileReading,
                    onBookmark: serverDeleteController.setDeleteWithBookmark,
                    targetIdPrefix: 'server',
                  ),
                  SettingsGroupHeading(label: context.l10n.autoDownload),
                  if (personalState == PersonalSettingsState.unavailable)
                    ListTile(
                      title: Text(context.l10n.accountSettingsUnavailable),
                    ),
                  SettingsGroupCard(
                    children: [
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
                        id: 'excludeEntryWithUnreadChapters',
                        child: SettingsPropTile(
                          title: context.l10n.excludeEntryWithUnreadChapters,
                          type: SettingsPropType.switchTile(
                            value: downloadsSettingsDto
                                .excludeEntryWithUnreadChapters,
                            onChanged: canEditPersonal
                                ? repository
                                      .toggleExcludeEntryWithUnreadChapters
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
                            builder: (_) =>
                                const AutoDownloadCategoriesDialog(),
                            animationStyle: context.motionStyle,
                          ),
                        ),
                      ),
                      SettingsHighlightTarget(
                        id: 'chapterDownloadLimit',
                        child: SettingsPropTile(
                          title: context.l10n.chapterDownloadLimit,
                          description: context.l10n.chapterDownloadLimitDesc,
                          type: SettingsPropType.numberSlider(
                            value: downloadsSettingsDto
                                .autoDownloadNewChaptersLimit,
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
                      if (ref
                              .watch(autoDownloadIgnoreReUploadsProvider)
                              .value !=
                          null)
                        SettingsHighlightTarget(
                          id: 'ignoreReuploadedChapters',
                          child: SettingsPropTile(
                            title: context.l10n.ignoreReuploadedChapters,
                            type: SettingsPropType.switchTile(
                              value:
                                  ref
                                      .watch(
                                        autoDownloadIgnoreReUploadsProvider,
                                      )
                                      .value ??
                                  false,
                              onChanged:
                                  canEditPersonal &&
                                      downloadsSettingsDto
                                          .autoDownloadNewChapters
                                  ? (value) async {
                                      final result = await AppUtils.guard(
                                        () => repository
                                            .toggleAutoDownloadIgnoreReUploads(
                                              value,
                                            ),
                                        ref.read(toastProvider),
                                      );
                                      if (result != null && context.mounted) {
                                        ref.invalidate(
                                          autoDownloadIgnoreReUploadsProvider,
                                        );
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
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
    return SettingsHighlightScope(
      child: Center(
        child: ConstrainedBox(
          constraints: settingsPageConstraints(context),
          child: ListView(
            padding: settingsPagePadding(context),
            children: buildOnDeviceStorageTiles(context, ref),
          ),
        ),
      ),
    );
  }
}
