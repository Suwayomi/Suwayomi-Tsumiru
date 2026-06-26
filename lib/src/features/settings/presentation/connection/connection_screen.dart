// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/db_keys.dart';
import '../../../../constants/endpoints.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/section_title.dart';
import '../server/widget/client/server_port_tile/server_port_tile.dart';
import '../server/widget/client/server_url_tile/server_url_tile.dart';
import 'inline_auth_section.dart';

class ConnectionScreen extends HookConsumerWidget {
  const ConnectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One-time migration: the separate "Server Port" toggle is retired in
    // favour of the URL being the single source of truth. If a user still has
    // the toggle on, fold the port into the URL and switch the toggle off so
    // every URL-building call site (which then reads the URL as-is) keeps
    // reaching the same server.
    useEffect(() {
      // Defer to after the frame: provider writes must not happen during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref.read(serverPortToggleProvider).ifNull()) return;
        final String url =
            ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial;
        final port = ref.read(serverPortProvider);
        if (port != null && url.isNotBlank) {
          final merged = Endpoints.baseApi(
            baseUrl: url,
            port: port,
            addPort: true,
            appendApiToUrl: false,
          );
          ref.read(serverUrlProvider.notifier).update(merged);
        }
        ref.read(serverPortToggleProvider.notifier).update(false);
      });
      return null;
    }, const []);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.connection),
      ),
      body: ListTileTheme(
        data: const ListTileThemeData(
          subtitleTextStyle: TextStyle(color: Colors.grey),
        ),
        child: ListView(
          children: [
            SectionTitle(title: context.l10n.serverAddress),
            const ServerUrlTile(),
            const InlineAuthSection(),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.web_rounded),
                title: Text(context.l10n.webUI),
                onTap: () {
                  final url = Endpoints.baseApi(
                    baseUrl: ref.read(serverUrlProvider),
                    port: ref.read(serverPortProvider),
                    addPort: ref.read(serverPortToggleProvider).ifNull(),
                    appendApiToUrl: false,
                  );
                  if (url.isNotBlank) {
                    launchUrlInWeb(context, url, ref.read(toastProvider));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
