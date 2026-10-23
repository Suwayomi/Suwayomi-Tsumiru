// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

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
