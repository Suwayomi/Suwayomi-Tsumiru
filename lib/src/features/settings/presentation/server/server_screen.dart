// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../controller/server_controller.dart';
import 'widget/cloud_flare/cloud_flare_section.dart';
import 'widget/misc_settings/misc_settings_section.dart';
import 'widget/server_binding/server_binding_section.dart';
import 'widget/socks_proxy/socks_proxy_section.dart';

class ServerScreen extends ConsumerWidget {
  const ServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverSettings = ref.watch(settingsProvider);
    onRefresh() => ref.refresh(settingsProvider.future);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.server),
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListTileTheme(
          data: const ListTileThemeData(
            subtitleTextStyle: TextStyle(color: Colors.grey),
          ),
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  context.l10n.serverOwnSettingsCaption,
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ),
              if (serverSettings.isLoading && !serverSettings.hasValue)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (serverSettings.valueOrNull != null) ...[
                ServerBindingSection(serverBindingDto: serverSettings.value!),
                SocksProxySection(socksProxyDto: serverSettings.value!),
                CloudFlareSection(cloudFlareDto: serverSettings.value!),
                MiscSettingsSection(miscSettingsDto: serverSettings.value!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
