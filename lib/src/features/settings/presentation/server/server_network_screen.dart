import 'package:flutter/material.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'server_page_shell.dart';
import 'widget/cloud_flare/cloud_flare_section.dart';
import 'widget/server_binding/server_binding_section.dart';
import 'widget/socks_proxy/socks_proxy_section.dart';
import 'widget/webview/webview_section.dart';

class ServerNetworkScreen extends StatelessWidget {
  const ServerNetworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ServerSettingsPageShell(
      title: Text(context.l10n.network),
      whenData: (data) => [
        ServerBindingSection(serverBindingDto: data),
        SocksProxySection(socksProxyDto: data),
        CloudFlareSection(cloudFlareDto: data),
        const WebViewSection(),
      ],
    );
  }
}
