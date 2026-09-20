// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

CacheManager createCoverCacheManager({String? serverOrigin}) =>
    _BrowserImageCacheManager(_ServerImageClient(serverOrigin));

class _ServerImageClient extends http.BaseClient {
  _ServerImageClient(this.serverOrigin);

  final String? serverOrigin;
  final _server = BrowserClient()..withCredentials = true;
  final _external = BrowserClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final uri = request.url;
    final isServer =
        serverOrigin != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.origin == serverOrigin;
    return (isServer ? _server : _external).send(request);
  }

  @override
  void close() {
    _server.close();
    _external.close();
    super.close();
  }
}

class _BrowserImageCacheManager extends CacheManager {
  _BrowserImageCacheManager(this.client)
    : super(
        Config(
          'tsumiruWebImages',
          fileService: HttpFileService(httpClient: client),
        ),
      );

  final http.Client client;

  @override
  Future<void> dispose() async {
    client.close();
    await super.dispose();
  }
}
