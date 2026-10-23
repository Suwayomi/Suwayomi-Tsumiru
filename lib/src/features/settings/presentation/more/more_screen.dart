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
import '../../../account/presentation/sign_out_action.dart';
import '../../../auth/data/auth_session_status.dart';
import '../../../auth/data/auth_state.dart';
import '../../../manga_book/data/updates/updates_repository.dart';
import '../../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../../quick_open/presentation/unified_search/unified_search_providers.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';
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
    final hasStoredCredentials = ref.watch(hasStoredCredentialsProvider);
    final incognito = ref.watch(incognitoModeProvider);
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

    Widget accountSection() {
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
        ConnectionAuthStatus.signedIn => context.l10n.connectionAuthSignedIn,
        ConnectionAuthStatus.noAuth => context.l10n.connectionAuthNone,
        ConnectionAuthStatus.signInNeeded =>
          context.l10n.connectionAuthSignInNeeded,
      };
      const chevron = Icon(Icons.chevron_right_rounded);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsGroupHeading(label: context.l10n.accountTitle),
          SettingsGroupCard(
            children: [
              if (showAccount)
                SettingsGroupRow(
                  icon: Icons.person_outlined,
                  title: account?.username ?? context.l10n.accountTitle,
                  subtitle: host.isEmpty ? null : host,
                  trailing: chevron,
                  onTap: () => const ConnectionRoute().push(context),
                )
              else
                SettingsGroupRow(
                  icon: Icons.dns_outlined,
                  title: host.isEmpty ? context.l10n.connection : host,
                  subtitle: statusLabel,
                  trailing: chevron,
                  onTap: () => const ConnectionRoute().push(context),
                ),
              if (showAccount && hasStoredCredentials)
                ListTile(
                  leading: Icon(
                    Icons.logout_outlined,
                    color: context.theme.colorScheme.error,
                  ),
                  title: Text(
                    context.l10n.accountSignOut,
                    style: TextStyle(color: context.theme.colorScheme.error),
                  ),
                  onTap: () => confirmAndSignOutAccount(context, ref),
                ),
            ],
          ),
        ],
      );
    }

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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              children: [
                if (!context.usesDesktopShell) ...[
                  TsumiruLogo(size: context.height * .2),
                ],
                accountSection(),
                SettingsGroupHeading(label: context.l10n.library),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: Icons.visibility_off_outlined,
                      title: context.l10n.incognitoMode,
                      subtitle: context.l10n.incognitoModeDescription,
                      trailing: Switch(
                        value: incognito,
                        onChanged: (value) =>
                            ref.read(incognitoModeProvider.notifier).set(value),
                      ),
                      onTap: () => ref
                          .read(incognitoModeProvider.notifier)
                          .set(!incognito),
                    ),
                    SettingsGroupRow(
                      icon: Icons.label_outlined,
                      title: context.l10n.categories,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => const EditCategoriesRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.history_outlined,
                      title: context.l10n.history,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => const HistoryRoute().push(context),
                    ),
                    Builder(
                      builder: (context) {
                        final count =
                            ref.watch(failedUpdateCountProvider).value ?? 0;
                        return SettingsGroupRow(
                          icon: Icons.error_outline,
                          title: context.l10n.libraryUpdateErrorsCount(count),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () =>
                              const LibraryUpdateErrorsRoute().push(context),
                        );
                      },
                    ),
                    SettingsGroupRow(
                      icon: Icons.settings_backup_restore_outlined,
                      title: context.l10n.backup,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => const BackupRoute().push(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: Icons.color_lens_outlined,
                      title: context.l10n.appearance,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          const AppearanceSettingsRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.settings_outlined,
                      title: context.l10n.settings,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => const SettingsRoute().push(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroupCard(
                  children: [
                    SettingsGroupRow(
                      icon: Icons.info_outlined,
                      title: context.l10n.about,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => const AboutRoute().push(context),
                    ),
                    SettingsGroupRow(
                      icon: Icons.help_outline_rounded,
                      title: context.l10n.help,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => launchUrlInWeb(
                        context,
                        AppUrls.tachideskHelp.url,
                        ref.read(toastProvider),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return topBar
        ? TopBarSlot(
            content: desktopSearchSlotContent(
              search: search,
              actions: const [],
            ),
            minWidth: searchTopBarSlotMinWidth(0),
            child: scaffold,
          )
        : scaffold;
  }
}
