import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'server_page_shell.dart';
import 'widget/sign_in/sign_in_section.dart';

class ServerSignInScreen extends StatelessWidget {
  const ServerSignInScreen({super.key});

  @override
  Widget build(BuildContext context) => ServerSettingsPageShell(
    title: Text(context.l10n.serverSignIn),
    whenData: (_) => const [SignInSection()],
  );
}
