import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'server_page_shell.dart';
import 'widget/misc_settings/misc_settings_section.dart';

class ServerLogsScreen extends StatelessWidget {
  const ServerLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ServerSettingsPageShell(
      title: Text(context.l10n.logs),
      whenData: (data) => [MiscSettingsSection(miscSettingsDto: data)],
    );
  }
}
