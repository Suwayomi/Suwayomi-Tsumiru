// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/enum.dart';
import '../../../../constants/urls.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/tsumiru_logo.dart';
import '../../../../widgets/web_selection_area.dart';
import '../../../account/data/account_providers.dart';
import '../../../auth/data/auth_session_status.dart';
import '../../../auth/data/auth_state.dart';
import '../../../manga_book/data/updates/updates_repository.dart';
import '../../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../../quick_open/presentation/unified_search/unified_search_providers.dart';
import '../connection/connection_status.dart';
import '../incognito/incognito_mode.dart';
import '../library/widgets/persistent_search_bar/persistent_search_bar.dart';
import '../server/widget/client/server_port_tile/server_port_tile.dart';
import '../server/widget/client/server_url_tile/server_url_tile.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authType = ref.watch(authTypeKeyProvider);
    final account = ref.watch(currentAccountProvider);
    final showAccount = ref.watch(showAccountEntryProvider);
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    // Phone searches from the app-bar entry (or the box under the title when
    // the persistent setting is on); tablet and desktop are unchanged.
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();
    // Native desktop draws the search box in the shell bar instead of an
    // app bar.
    final topBar = showsMergedTopBar(context);
    final search = DesktopSearchField(
      query: ref.watch(unifiedSearchQueryProvider),
      onChanged: (value) =>
          ref.read(unifiedSearchQueryProvider.notifier).state = value,
      onNavigate: () =>
          ref.read(unifiedSearchQueryProvider.notifier).state = '',
    );
    final scaffold = Scaffold(
      // Desktop replaces the title with the unified search box (the sidebar
      // already names the page); phone and tablet keep it.
      appBar: topBar
          ? null
          : AppBar(
              title: context.usesDesktopShell
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: search,
                      ),
                    )
                  : Text(context.l10n.more),
              bottom: persistentBox
                  ? const PhoneSearchBoxBottom(origin: PhoneSearchOrigin.plain)
                  : null,
              actions: [
                if (phone && !persistentBox)
                  const PhoneSearchEntry(origin: PhoneSearchOrigin.plain),
              ],
            ),
      body: WebSelectionArea(
        child: ListView(
          children: [
            if (!context.usesDesktopShell) ...[
              TsumiruLogo(size: context.height * .2),
              const Divider(),
            ],
            Builder(
              builder: (context) {
                final host = formatServerHost(
                  ref.watch(serverUrlProvider),
                  ref.watch(serverPortProvider),
                  ref.watch(serverPortToggleProvider).ifNull(),
                );
                final statusLabel = switch (connectionAuthStatus(
                  ref.watch(authTypeKeyProvider),
                  ref.watch(needsReauthProvider) ||
                      ((authType ?? AuthType.none) != AuthType.none &&
                          !ref.watch(hasStoredCredentialsProvider)),
                )) {
                  ConnectionAuthStatus.signedIn =>
                    context.l10n.connectionAuthSignedIn,
                  ConnectionAuthStatus.noAuth => context.l10n.connectionAuthNone,
                  ConnectionAuthStatus.signInNeeded =>
                    context.l10n.connectionAuthSignInNeeded,
                };
                final subtitle = host.isEmpty
                    ? statusLabel
                    : '$host · $statusLabel';
                return ListTile(
                  leading: const Icon(Icons.dns_rounded),
                  title: Text(context.l10n.connection),
                  subtitle: Text(subtitle),
                  onTap: () => const ConnectionRoute().push(context),
                );
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.no_accounts_rounded),
              title: Text(context.l10n.incognitoMode),
              subtitle: Text(context.l10n.incognitoModeDescription),
              value: ref.watch(incognitoModeProvider),
              onChanged: (value) =>
                  ref.read(incognitoModeProvider.notifier).set(value),
            ),
            if (showAccount)
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: Text(context.l10n.accountTitle),
                subtitle: account == null ? null : Text(account.username),
                onTap: () => const AccountRoute().push(context),
              ),
            ListTile(
              title: Text(context.l10n.categories),
              leading: const Icon(Icons.label_rounded),
              onTap: () => const EditCategoriesRoute().push(context),
            ),
            ListTile(
              title: Text(context.l10n.history),
              leading: const Icon(Icons.history_rounded),
              onTap: () => const HistoryRoute().push(context),
            ),
            Builder(
              builder: (context) {
                final count = ref.watch(failedUpdateCountProvider).value ?? 0;
                return ListTile(
                  title: Text(context.l10n.libraryUpdateErrorsCount(count)),
                  leading: const Icon(Icons.error_outline_rounded),
                  onTap: () => const LibraryUpdateErrorsRoute().push(context),
                );
              },
            ),
            ListTile(
              title: Text(context.l10n.appearance),
              leading: const Icon(Icons.color_lens_rounded),
              onTap: () => const AppearanceSettingsRoute().push(context),
            ),
            ListTile(
              title: Text(context.l10n.backup),
              leading: const Icon(Icons.settings_backup_restore_rounded),
              onTap: () => const BackupRoute().push(context),
            ),
            const Divider(),
            ListTile(
              title: Text(context.l10n.settings),
              leading: const Icon(Icons.settings_rounded),
              onTap: () => const SettingsRoute().push(context),
            ),
            ListTile(
              title: Text(context.l10n.about),
              leading: const Icon(Icons.info_rounded),
              onTap: () => const AboutRoute().push(context),
            ),
            ListTile(
              title: Text(context.l10n.help),
              leading: const Icon(Icons.help_rounded),
              onTap: () => launchUrlInWeb(
                context,
                AppUrls.tachideskHelp.url,
                ref.read(toastProvider),
              ),
            ),
          ],
        ),
      ),
    );
    return topBar
        ? TopBarSlot(
            content: desktopSearchSlotContent(search: search, actions: const []),
            minWidth: searchTopBarSlotMinWidth(0),
            child: scaffold,
          )
        : scaffold;
  }
}
