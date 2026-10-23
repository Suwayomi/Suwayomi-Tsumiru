import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../account/data/account_providers.dart';

class ServerScreen extends ConsumerWidget {
  const ServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(settledAccountAccessProvider)
        .allows(Enum$UserPermission.MANAGE_SETTINGS);
    final List<Widget> rows = [
      _HubRow(
        icon: Icons.dns_outlined,
        title: context.l10n.network,
        onTap: () => const ServerNetworkRoute().push(context),
      ),
      if (canManage)
        _HubRow(
          icon: Icons.web_outlined,
          title: context.l10n.webInterface,
          onTap: () => const ServerWebInterfaceRoute().push(context),
        ),
      _HubRow(
        icon: Icons.rss_feed_outlined,
        title: context.l10n.opds,
        onTap: () => const ServerOpdsRoute().push(context),
      ),
      _HubRow(
        icon: Icons.image_outlined,
        title: context.l10n.images,
        onTap: () => const ServerImagesRoute().push(context),
      ),
      if (canManage)
        _HubRow(
          icon: Icons.storage_outlined,
          title: context.l10n.database,
          onTap: () => const ServerDatabaseRoute().push(context),
        ),
      if (canManage)
        _HubRow(
          icon: Icons.receipt_long_outlined,
          title: context.l10n.logs,
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
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) => rows[index],
            separatorBuilder: (context, index) => const Divider(),
            itemCount: rows.length,
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

class _HubRow extends StatelessWidget {
  const _HubRow({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: context.theme.colorScheme.onSurfaceVariant),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
