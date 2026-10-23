import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'server_page_shell.dart';
import 'widget/database/database_section.dart';

class ServerDatabaseScreen extends StatelessWidget {
  const ServerDatabaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ServerSettingsPageShell(
      title: Text(context.l10n.database),
      whenData: (_) => const [DatabaseSection()],
    );
  }
}
