import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'server_page_shell.dart';
import 'widget/opds/opds_section.dart';

class ServerOpdsScreen extends StatelessWidget {
  const ServerOpdsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ServerSettingsPageShell(
      title: Text(context.l10n.opds),
      whenData: (_) => const [OpdsSection()],
    );
  }
}
