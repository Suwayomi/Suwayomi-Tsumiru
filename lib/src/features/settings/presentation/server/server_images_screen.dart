import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'server_page_shell.dart';
import 'widget/images/images_section.dart';

class ServerImagesScreen extends StatelessWidget {
  const ServerImagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ServerSettingsPageShell(
      title: Text(context.l10n.images),
      whenData: (_) => const [ImagesSection()],
    );
  }
}
