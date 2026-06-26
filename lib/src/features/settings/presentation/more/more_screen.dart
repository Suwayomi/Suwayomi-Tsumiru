// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/gen/assets.gen.dart';
import '../../../../constants/urls.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../auth/data/auth_state.dart';
import '../connection/connection_status.dart';
import '../incognito/incognito_mode.dart';
import '../server/widget/client/server_port_tile/server_port_tile.dart';
import '../server/widget/client/server_url_tile/server_url_tile.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.more),
      ),
      body: ListView(
        children: [
          ImageIcon(
            AssetImage(Assets.icons.darkIcon.path),
            size: context.height * .2,
          ),
          const Divider(),
          Builder(
            builder: (context) {
              final host = formatServerHost(
                ref.watch(serverUrlProvider),
                ref.watch(serverPortProvider),
                ref.watch(serverPortToggleProvider).ifNull(),
              );
              final statusLabel = switch (connectionAuthStatus(
                ref.watch(authTypeKeyProvider),
                ref.watch(needsReauthProvider),
              )) {
                ConnectionAuthStatus.signedIn =>
                  context.l10n.connectionAuthSignedIn,
                ConnectionAuthStatus.noAuth => context.l10n.connectionAuthNone,
                ConnectionAuthStatus.signInNeeded =>
                  context.l10n.connectionAuthSignInNeeded,
              };
              final subtitle =
                  host.isEmpty ? statusLabel : '$host · $statusLabel';
              return ListTile(
                leading: const Icon(Icons.dns_rounded),
                title: Text(context.l10n.connection),
                subtitle: Text(subtitle),
                onTap: () => const ConnectionRoute().go(context),
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
          ListTile(
            title: Text(context.l10n.categories),
            leading: const Icon(Icons.label_rounded),
            onTap: () => const EditCategoriesRoute().push(context),
          ),
          ListTile(
            title: Text(context.l10n.history),
            leading: const Icon(Icons.history_rounded),
            onTap: () => const HistoryRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.appearance),
            leading: const Icon(Icons.color_lens_rounded),
            onTap: () => const AppearanceSettingsRoute().go(context),
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
            onTap: () => const SettingsRoute().go(context),
          ),
          ListTile(
            title: Text(context.l10n.about),
            leading: const Icon(Icons.info_rounded),
            onTap: () => const AboutRoute().go(context),
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
    );
  }
}
