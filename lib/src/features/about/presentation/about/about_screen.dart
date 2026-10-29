// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../../../constants/app_constants.dart';
import '../../../../constants/app_distribution.dart';
import '../../../../constants/app_sizes.dart';
import '../../../../constants/brand_icons.dart';
import '../../../../constants/urls.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../../widgets/tsumiru_logo.dart';
import '../../../../widgets/web_selection_area.dart';
import '../../../settings/presentation/settings/settings_pane_scope.dart';
import '../../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../../data/about_repository.dart';
import '../../data/macos_app_updater.dart';
import '../../domain/about/about_dto.dart';
import '../../domain/server_update/server_update.dart';
import 'controllers/about_controller.dart';
import 'widget/app_update_dialog.dart';
import 'widget/clipboard_list_tile.dart';
import 'widget/debug_information_tile.dart';
import 'widget/media_launch_button.dart';
import 'widget/server_update_alert_tiles.dart';

class AboutScreen extends HookConsumerWidget {
  const AboutScreen({super.key});

  void checkForServerUpdate({
    required BuildContext context,
    required String serverVer,
    required AboutDto about,
    required Future<List<ServerUpdate>?> Function() updateCallback,
    required Toast? toast,
  }) {
    toast?.show(context.l10n.searchingForUpdates);
    AsyncValue.guard(updateCallback).then((value) {
      toast?.close();
      if (!context.mounted) return;
      try {
        value.whenOrNull(
          data: (data) {
            if (data == null) return;
            final newUpdate = data.firstWhere(
              (e) => e.channel == about.buildType,
              orElse: () => ServerUpdate(),
            );
            final currentVer = Version.parse(serverVer.substring(1));
            final newVer = Version.parse(newUpdate.tag?.substring(1) ?? "");
            if ((newVer.compareTo(currentVer)).isGreaterThan(0)) {
              appUpdateDialog(
                title: about.name,
                newRelease:
                    "${newVer.canonicalizedVersion}"
                    " (${newUpdate.channel})",
                context: context,
                toast: toast,
                url: newUpdate.url,
                isServerUpdate: true,
              );
            } else {
              toast?.show(context.l10n.noUpdatesAvailable);
            }
          },
          error: (error, stackTrace) {
            if (toast != null) {
              value.showToastOnError(toast);
            }
          },
        );
      } catch (e) {
        if (context.mounted) {
          toast?.showError(
            kDebugMode ? e.toString() : context.l10n.errorSomethingWentWrong,
          );
        }
      }
    });
  }

  Future<void> checkForUpdate({
    required String? title,
    required BuildContext context,
    required Future<AsyncValue<Version?>> Function() updateCallback,
    required Toast? toast,
  }) async {
    toast?.show(context.l10n.searchingForUpdates);
    final result = await updateCallback();
    if (!context.mounted) return;
    toast?.close();
    result.whenOrNull(
      data: (version) {
        if (version != null) {
          appUpdateDialog(
            title: title ?? kAppName,
            newRelease: "v${version.canonicalizedVersion}",
            context: context,
            toast: toast,
          );
        } else {
          toast?.show(context.l10n.noUpdatesAvailable);
        }
      },
      error: (error, stackTrace) {
        if (toast != null) {
          result.showToastOnError(toast);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    final aboutAsync = ref.watch(aboutProvider);
    final about = aboutAsync.value;
    final webUi = ref.watch(aboutWebUIProvider).value;
    // Server version already includes revision as its patch number.
    final serverVer = about?.version;
    final packageInfo = ref.watch(packageInfoProvider);
    final serverHosted = ref.watch(serverHostedWebProvider);

    useEffect(() {
      if (toast != null) {
        aboutAsync.showToastOnError(toast, withMicrotask: true);
      }
      return;
    }, [aboutAsync.value]);

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.about);
    final inSettingsWindow = SettingsPaneScope.maybeOf(context) != null;
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(leading: detailNavigationBackButton(context), title: title),
      body: WebSelectionArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(aboutProvider.future),
          child: Center(
            child: ConstrainedBox(
              constraints: settingsPageConstraints(context),
              child: ListView(
                padding: settingsPagePadding(context),
                children: [
                  if (inSettingsWindow)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 8, 16, 0),
                      child: Row(
                        children: [
                          const TsumiruLogo(size: 48),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kAppName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'v${packageInfo.version}',
                                style: context.textTheme.bodyMedium?.copyWith(
                                  color: context
                                      .theme
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (inSettingsWindow) const SizedBox(height: 12),
                  if (!inSettingsWindow) TsumiruLogo(size: context.height * .2),
                  SettingsGroupHeading(label: context.l10n.client, first: true),
                  SettingsGroupCard(
                    children: [
                      ClipboardListTile(
                        title: context.l10n.client,
                        value: packageInfo.appName,
                      ),
                      ClipboardListTile(
                        title: context.l10n.clientVersion,
                        value: "v${packageInfo.version}",
                      ),
                      ListTile(
                        title: Text(context.l10n.whatsNew),
                        onTap: () async {
                          await launchUrlInWeb(
                            context,
                            AppUrls.whatsNew.url,
                            toast,
                          );
                        },
                      ),
                      ListTile(
                        title: Text(context.l10n.helpTranslate),
                        onTap: () async {
                          await launchUrlInWeb(
                            context,
                            AppUrls.weblateTranslate.url,
                            toast,
                          );
                        },
                      ),
                      if (!isGooglePlayBuild)
                        ListTile(
                          title: Text(
                            serverHosted
                                ? context.l10n.updatedByYourServer
                                : context.l10n.checkForUpdates,
                          ),
                          onTap: serverHosted
                              ? () => const ServerSettingsRoute().push(context)
                              : () async {
                                  final nativeUpdater = ref.read(
                                    macOSAppUpdaterProvider,
                                  );
                                  if (nativeUpdater.isAvailable &&
                                      await nativeUpdater.checkForUpdates()) {
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  await checkForUpdate(
                                    title: packageInfo.appName,
                                    context: context,
                                    updateCallback: ref
                                        .read(aboutRepositoryProvider)
                                        .checkUpdate,
                                    toast: toast,
                                  );
                                },
                        ),
                      ListTile(
                        title: Text(context.l10n.privacyPolicy),
                        onTap: () => launchUrlInWeb(
                          context,
                          AppUrls.privacyPolicy.url,
                          toast,
                        ),
                      ),
                    ],
                  ),
                  if (about != null) ...[
                    SettingsGroupHeading(label: context.l10n.server),
                    SettingsGroupCard(
                      children: [
                        ClipboardListTile(
                          title: context.l10n.server,
                          value: about.name,
                        ),
                        ClipboardListTile(
                          title: context.l10n.channel,
                          value: about.buildType,
                        ),
                        if (serverVer.isNotBlank)
                          ClipboardListTile(
                            title: context.l10n.serverVersion,
                            value: serverVer,
                          ),
                        ClipboardListTile(
                          title: context.l10n.buildTime,
                          value: about.buildTime.toDateString,
                        ),
                        if (serverVer.isNotBlank)
                          ListTile(
                            title: Text(context.l10n.checkForServerUpdates),
                            onTap: () => checkForServerUpdate(
                              context: context,
                              serverVer: serverVer ?? "",
                              about: about,
                              updateCallback: ref
                                  .read(aboutRepositoryProvider)
                                  .checkServerUpdate,
                              toast: toast,
                            ),
                          ),
                        const ServerUpdateAlertTiles(),
                        DebugInformationTile(
                          about: about,
                          webUiFlavor: webUi?.channel.name,
                          webUiVersion: webUi?.tag,
                        ),
                      ],
                    ),
                  ],
                  Padding(
                    padding: KEdgeInsets.a8.size,
                    child: Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      children: [
                        MediaLaunchButton(
                          title: context.l10n.githubTsumiru,
                          icon: Icon(BrandIcons.github),
                          url: AppUrls.githubUrl.url,
                          toast: toast,
                        ),
                        if ((about?.github).isNotBlank)
                          MediaLaunchButton(
                            title: context.l10n.githubServer,
                            icon: Icon(BrandIcons.github),
                            url: about!.github,
                          toast: toast,
                        ),
                        if ((about?.discord).isNotBlank)
                          MediaLaunchButton(
                            title: context.l10n.discord,
                            icon: Icon(BrandIcons.discord),
                            url: about!.discord,
                            toast: toast,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}
