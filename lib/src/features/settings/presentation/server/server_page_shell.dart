// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/network/graphql_errors.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/server_unreachable_view.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../account/data/account_providers.dart';
import '../../controller/server_controller.dart';
import '../../domain/settings/settings.dart';
import '../../search/settings_search_registry.dart';
import 'data/web_interface_repository.dart';
import 'widget/database/data/database_repository.dart';
import 'widget/images/data/images_repository.dart';
import 'widget/misc_settings/data/misc_logs_repository.dart';
import 'widget/opds/data/opds_repository.dart';
import 'widget/webview/data/webview_repository.dart';

List<Widget> _noSections(SettingsDto _) => const [];

class ServerSettingsPageShell extends ConsumerWidget {
  const ServerSettingsPageShell({
    super.key,
    required this.title,
    this.always = const [],
    this.whenData = _noSections,
    this.showPermissionNotice = true,
  });

  final Widget title;
  final List<Widget> always;
  final List<Widget> Function(SettingsDto data) whenData;
  final bool showPermissionNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final serverSettings = ref.watch(settingsProvider);
    Future<void> onRefresh() async {
      ref.invalidate(webInterfaceSettingsProvider);
      ref.invalidate(webInterfaceFlavorsProvider);
      ref.invalidate(installedWebInterfaceProvider);
      ref.invalidate(opdsSettingsProvider);
      ref.invalidate(databaseSettingsProvider);
      ref.invalidate(miscLogsSettingsProvider);
      ref.invalidate(webViewSettingsProvider);
      ref.invalidate(clearCookiesAndCacheSupportProvider);
      ref.invalidate(imagesDownloadSettingsProvider);
      ref.invalidate(serveConversionsProvider);
      ref.invalidate(clearCachedImagesSupportProvider);
      ref.invalidate(settingsProvider);
      await ref.read(settingsProvider.future);
    }

    final topBar = showsMergedTopBar(context);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(leading: detailNavigationBackButton(context), title: title),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListTileTheme(
          data: ListTileThemeData(
            subtitleTextStyle: TextStyle(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
          child: SettingsHighlightScope(
            child: Center(
              child: ConstrainedBox(
                constraints: settingsPageConstraints(context),
                child: ListView(
                  padding: settingsPagePadding(context),
                  children: [
                    if (serverSettings.isLoading && !serverSettings.hasValue)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (serverSettings.hasError && !serverSettings.hasValue)
                      Builder(
                        builder: (context) {
                          final error = serverSettings.error!;
                          final unwrapped = error is OperationMessageException
                              ? error.exception
                              : error;
                          if (isConnectionError(unwrapped)) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: ServerUnreachableView(onRetry: onRefresh),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(child: Text(error.toString())),
                          );
                        },
                      ),
                    if (!canManage && showPermissionNotice)
                      ListTile(
                        subtitle: Text(
                          context.l10n.manageSettingsPermissionRequired,
                        ),
                      ),
                    ...always,
                    if (serverSettings.value != null)
                      ...whenData(serverSettings.value!),
                  ],
                ),
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
