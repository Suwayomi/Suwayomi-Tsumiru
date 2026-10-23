import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'server_page_shell.dart';
import 'widget/web_interface/web_interface_section.dart';

class ServerWebInterfaceScreen extends StatelessWidget {
  const ServerWebInterfaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ServerSettingsPageShell(
      title: Text(context.l10n.webInterface),
      always: const [WebInterfaceSection()],
    );
  }
}
