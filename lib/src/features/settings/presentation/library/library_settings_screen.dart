// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/db_keys.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/input_popup/domain/settings_prop_type.dart';
import '../../../../widgets/input_popup/settings_prop_tile.dart';
import '../../../../widgets/popup_widgets/radio_list_popup.dart';
import '../../../../widgets/section_title.dart';
import '../../../library/domain/category/category_model.dart';
import '../../../library/presentation/category/controller/edit_category_controller.dart';
import '../../../library/presentation/library/controller/library_controller.dart';
import '../../controller/server_controller.dart';
import '../../domain/settings/settings.dart';
import 'data/library_settings_repository.dart';
import 'widgets/refresh_chapters_from_source_tile/refresh_chapters_from_source_tile.dart';
import 'widgets/show_update_progress_banner/show_update_progress_banner.dart';
import 'widgets/skip_updating_entries_popup.dart';
import 'widgets/update_categories_dialog.dart';

class LibrarySettingsScreen extends ConsumerWidget {
  const LibrarySettingsScreen({super.key});

  @override
  Widget build(context, ref) {
    final repository = ref.watch(librarySettingsRepositoryProvider);
    final serverSettings = ref.watch(settingsProvider);
    final categories = ref.watch(categoryControllerProvider).value ??
        const <CategoryDto>[];

    return ListTileTheme(
      data: const ListTileThemeData(
        subtitleTextStyle: TextStyle(color: Colors.grey),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.library),
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(settingsProvider.future),
          child: serverSettings.showUiWhenData(
            context,
            (data) {
              final LibrarySettingsDto? librarySettingsDto = data;
              if (librarySettingsDto == null) {
                return Emoticons(
                  title: context.l10n.noPropFound(context.l10n.settings),
                );
              }
              final skipUpdatingEntriesList = [
                if (librarySettingsDto.excludeCompleted)
                  context.l10n.withCompletedStatus,
                if (librarySettingsDto.excludeNotStarted)
                  context.l10n.thatHaventBeenStarted,
                if (librarySettingsDto.excludeUnreadChapters)
                  context.l10n.withUnreadChapter,
              ];
              final defaultCategory =
                  ref.watch(libraryDefaultCategoryProvider) ??
                      DBKeys.libraryDefaultCategory.initial as int;
              final defaultCategoryMatch =
                  categories.where((c) => c.id == defaultCategory);
              final defaultCategoryLabel = defaultCategory == -1 ||
                      defaultCategoryMatch.isEmpty
                  ? context.l10n.alwaysAsk
                  : defaultCategoryMatch.first.name;
              void onAutomaticUpdateIntervalUpdate(int value) async {
                final result = await AppUtils.guard(
                    () =>
                        repository.updateGlobalUpdateInterval(value.toDouble()),
                    ref.read(toastProvider));
                if (result != null) {
                  ref.read(settingsProvider.notifier).updateState(result);
                }
              }

              return ListView(
                children: [
                  SectionTitle(title: context.l10n.general),
                  ListTile(
                    title: Text(context.l10n.categories),
                    leading: const Icon(Icons.label_rounded),
                    onTap: () => const EditCategoriesRoute().go(context),
                  ),
                  ListTile(
                    title: Text(context.l10n.defaultCategoryOnAdd),
                    leading: const Icon(Icons.folder_special_outlined),
                    subtitle: Text(defaultCategoryLabel),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => RadioListPopup<int>(
                        title: context.l10n.defaultCategoryOnAdd,
                        optionList: [-1, ...categories.map((c) => c.id)],
                        value: defaultCategory,
                        getOptionTitle: (v) => v == -1
                            ? context.l10n.alwaysAsk
                            : categories
                                .firstWhere((c) => c.id == v)
                                .name,
                        onChange: (v) {
                          ref
                              .read(libraryDefaultCategoryProvider.notifier)
                              .update(v);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
                  // HideEmptyCategoryTile(),
                  const RefreshChaptersFromSourceTile(),
                  SectionTitle(title: context.l10n.globalUpdate),
                  const ShowUpdateProgressBannerTile(),
                  SettingsPropTile(
                    leading: const Icon(Icons.autorenew_rounded),
                    title: context.l10n.automaticUpdate,
                    subtitle: librarySettingsDto.globalUpdateInterval.isNotZero
                        ? context.l10n.nHours(
                            librarySettingsDto.globalUpdateInterval.toInt())
                        : null,
                    trailing: Switch(
                      value: librarySettingsDto.globalUpdateInterval.isNotZero,
                      onChanged: (value) =>
                          onAutomaticUpdateIntervalUpdate(value ? 12 : 0),
                    ),
                    onTap: AppUtils.returnIf(
                      librarySettingsDto.globalUpdateInterval.isZero,
                      () => onAutomaticUpdateIntervalUpdate(12),
                    ),
                    type: SettingsPropType.numberPicker(
                      min: 1,
                      max: 10000000,
                      value: librarySettingsDto.globalUpdateInterval.toInt(),
                      onChanged: (value) => repository
                          .updateGlobalUpdateInterval(value.toDouble()),
                    ),
                  ),
                  SettingsPropTile(
                    title: context.l10n.automaticallyRefreshMetadata,
                    trailing: const Icon(Icons.now_wallpaper_rounded),
                    subtitle: context.l10n.automaticallyRefreshMetadataSubtitle,
                    type: SettingsPropType.switchTile(
                      value: librarySettingsDto.updateMangas,
                      onChanged: (value) async {
                        final result = await AppUtils.guard(
                            () => repository.updateMangaMetaData(value),
                            ref.read(toastProvider));
                        if (result != null) {
                          ref
                              .read(settingsProvider.notifier)
                              .updateState(result);
                        }
                      },
                    ),
                  ),
                  ListTile(
                    title: Text(context.l10n.skipUpdatingEntries),
                    subtitle: Text(
                      skipUpdatingEntriesList.isNotBlank
                          ? skipUpdatingEntriesList.join(", ")
                          : context.l10n.none,
                    ),
                    onTap: () => showDialog(
                      context: context,
                      builder: (context) => const SkipUpdatingEntriesPopup(),
                    ),
                  ),
                  ListTile(
                    title: Text(context.l10n.updateCategories),
                    subtitle: Text(
                        libraryUpdateCategoriesSummary(context, categories)),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => const UpdateCategoriesDialog(),
                    ),
                  ),
                  // SectionTitle(title: context.l10n.advanced),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
