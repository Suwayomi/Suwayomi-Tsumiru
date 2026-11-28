// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../constants/endpoints.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/launch_url_in_web.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';

/// Uses the server web root without /api; returns null when no server is configured.
String? serverMangaWebUrl(WidgetRef ref, int mangaId) {
  final base = Endpoints.baseApi(
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
    appendApiToUrl: false,
  );
  if (base.isBlank) return null;
  final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$root/manga/$mangaId';
}

String serverWebViewUrl(String baseApi, String url) =>
    '${baseApi.endsWith('/') ? baseApi : '$baseApi/'}webview#$url';

void openServerWebView(BuildContext context, WidgetRef ref, String? url) {
  if (url == null || url.isBlank) return;
  final api = Endpoints.baseApi(
    baseUrl: ref.read(serverUrlProvider),
    port: ref.read(serverPortProvider),
    addPort: ref.read(serverPortToggleProvider).ifNull(),
  );
  launchUrlInWeb(context, serverWebViewUrl(api, url), ref.read(toastProvider));
}
