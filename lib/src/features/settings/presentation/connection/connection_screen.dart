// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/db_keys.dart';
import '../../../../constants/endpoints.dart';
import '../../../../constants/enum.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/network/cleartext_address.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../account/data/account_actions.dart';
import '../../../account/data/account_providers.dart';
import '../../../auth/data/auth_session_status.dart';
import '../../../offline/presentation/offline_server_mismatch_banner.dart';
import '../../search/settings_search_registry.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
import '../general/timeout_settings/timeout_settings_section.dart';
import '../server/widget/client/server_port_tile/server_port_tile.dart';
import '../server/widget/client/server_url_tile/server_url_tile.dart';
import 'connection_account_section.dart';
import 'custom_headers_section.dart';
import 'inline_auth_section.dart';

class ConnectionScreen extends HookConsumerWidget {
  const ConnectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeUrl =
        ref.watch(serverEndpointResolverProvider) ??
        ref.watch(serverUrlProvider) ??
        DBKeys.serverUrl.initial;
    final lanUrl = ref.watch(serverLanUrlProvider);
    final usesLan = lanUrl != null && activeUrl == lanUrl;
    final showLanAddress = useState(lanUrl != null);
    final authType = ref.watch(authTypeKeyProvider) ?? DBKeys.authType.initial;
    final showAccount = ref.watch(showAccountEntryProvider);
    final hasCredentials = ref.watch(hasStoredCredentialsProvider);
    final busy = useState(false);
    final actions = ref.read(accountActionsProvider);
    final toast = ref.read(toastProvider);
    final cleartext =
        authType != AuthType.none &&
        [
          ref.watch(serverExternalUrlProvider),
          lanUrl,
        ].any((url) => url != null && sendsCredentialsInClear(url));
    // Fold the legacy port toggle into the URL before URL-only callers read it.
    useEffect(() {
      // Defer to after the frame: provider writes must not happen during build.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!ref.read(serverPortToggleProvider).ifNull()) return;
        final String url =
            ref.read(serverExternalUrlProvider) ?? DBKeys.serverUrl.initial;
        final port = ref.read(serverPortProvider);
        if (port != null && url.isNotBlank) {
          final merged = Endpoints.baseApi(
            baseUrl: url,
            port: port,
            addPort: true,
            appendApiToUrl: false,
          );
          await ref.read(serverExternalUrlProvider.notifier).update(merged);
        }
        await ref.read(serverPortToggleProvider.notifier).update(false);
      });
      return null;
    }, const []);

    Future<void> refresh() async {
      if (busy.value || !hasCredentials) return;
      busy.value = true;
      try {
        await AppUtils.guard(actions.refreshAccount, toast);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.connection);
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: detailNavigationBackButton(context),
              title: title,
              actions: [
                if (showAccount)
                  IconButton(
                    tooltip: context.l10n.refresh,
                    onPressed: busy.value || !hasCredentials ? null : refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
      body: ListTileTheme(
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
                  // Keep recovery available after dismissal so offline mode can be re-enabled.
                  const OfflineServerMismatchBanner(showAfterDismissal: true),
                  SettingsGroupHeading(label: context.l10n.server, first: true),
                  SettingsGroupCard(
                    children: [
                      const SettingsHighlightTarget(
                        id: 'serverUrl',
                        child: ServerUrlTile(),
                      ),
                      if (showLanAddress.value || lanUrl != null)
                        const SettingsHighlightTarget(
                          id: 'serverLanUrl',
                          child: ServerLanUrlTile(),
                        )
                      else
                        ListTile(
                          title: Text(context.l10n.addLocalNetworkAddress),
                          onTap: () => showLanAddress.value = true,
                        ),
                      if (lanUrl != null)
                        ListTile(
                          title: Text(context.l10n.serverActiveUrl),
                          trailing: Chip(
                            label: Text(
                              usesLan
                                  ? context.l10n.serverUsingLanUrl
                                  : context.l10n.serverUsingExternalUrl,
                            ),
                          ),
                        ),
                      if (cleartext)
                        ListTile(
                          leading: Icon(
                            Icons.lock_open_rounded,
                            color: context.theme.colorScheme.error,
                          ),
                          subtitle: Text(
                            context.l10n.cleartextAddressWarning,
                            style: TextStyle(
                              color: context.theme.colorScheme.error,
                            ),
                          ),
                        ),
                      if (!kIsWeb)
                        SettingsHighlightTarget(
                          id: 'openInWeb',
                          child: ListTile(
                            title: Text(context.l10n.webUI),
                            onTap: () {
                              final url = Endpoints.baseApi(
                                baseUrl: ref.read(serverUrlProvider),
                                port: ref.read(serverPortProvider),
                                addPort: ref
                                    .read(serverPortToggleProvider)
                                    .ifNull(),
                                appendApiToUrl: false,
                              );
                              if (url.isNotBlank) {
                                launchUrlInWeb(
                                  context,
                                  url,
                                  ref.read(toastProvider),
                                );
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                  if (showAccount)
                    const ConnectionAccountSection()
                  else
                    const InlineAuthSection(),
                  const CustomHeadersSection(),
                  const TimeoutSettingsSection(),
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
      actions: [
        if (showAccount)
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: busy.value || !hasCredentials ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
      child: scaffold,
    );
  }
}
