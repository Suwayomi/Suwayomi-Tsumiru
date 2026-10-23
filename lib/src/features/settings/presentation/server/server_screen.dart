// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../account/data/account_providers.dart';
import '../../widgets/settings_group_card/settings_group_card.dart';

class ServerScreen extends ConsumerWidget {
  const ServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    const chevron = Icon(Icons.chevron_right_rounded);
    final List<Widget> rows = [
      if (canManage)
        SettingsGroupRow(
          icon: Icons.lan_outlined,
          title: context.l10n.network,
          trailing: chevron,
          onTap: () => const ServerNetworkRoute().push(context),
        ),
      if (canManage)
        SettingsGroupRow(
          icon: Icons.web_outlined,
          title: context.l10n.webInterface,
          trailing: chevron,
          onTap: () => const ServerWebInterfaceRoute().push(context),
        ),
      SettingsGroupRow(
        icon: Icons.rss_feed_outlined,
        title: context.l10n.opds,
        trailing: chevron,
        onTap: () => const ServerOpdsRoute().push(context),
      ),
      SettingsGroupRow(
        icon: Icons.image_outlined,
        title: context.l10n.images,
        trailing: chevron,
        onTap: () => const ServerImagesRoute().push(context),
      ),
      if (canManage)
        SettingsGroupRow(
          icon: Icons.storage_outlined,
          title: context.l10n.database,
          trailing: chevron,
          onTap: () => const ServerDatabaseRoute().push(context),
        ),
      if (canManage)
        SettingsGroupRow(
          icon: Icons.receipt_long_outlined,
          title: context.l10n.logs,
          trailing: chevron,
          onTap: () => const ServerLogsRoute().push(context),
        ),
    ];

    final topBar = showsMergedTopBar(context);
    final title = Text(context.l10n.serverAdmin);
    final scaffold = Scaffold(
      appBar: topBar ? null : AppBar(title: title),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [SettingsGroupCard(children: rows)],
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
