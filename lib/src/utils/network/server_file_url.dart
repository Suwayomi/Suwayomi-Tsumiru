// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../constants/endpoints.dart';

final _trailingSlashes = RegExp(r'/+$');
final _leadingSlashes = RegExp(r'^/+');

/// Join server-relative paths without duplicating /api/v1; blank paths return '' and must not be fetched.
String serverFileUrl({
  required String path,
  required String? baseUrl,
  required int? port,
  required bool addPort,
  required bool appendApiToUrl,
}) {
  if (path.isEmpty) return '';
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('file://')) {
    return path;
  }

  final hasApiPrefix = path.startsWith('/api/') || path.startsWith('api/');
  final origin = Endpoints.baseApi(
    baseUrl: baseUrl,
    port: port,
    addPort: addPort,
    appendApiToUrl: appendApiToUrl && !hasApiPrefix,
  );

  final root = origin.replaceAll(_trailingSlashes, '');
  final relative = path.replaceAll(_leadingSlashes, '');
  return '$root/$relative';
}

/// Absolute http(s) URL hosted anywhere but the configured server; those load
/// with no server credentials, so an unparsable server matches nothing.
bool isExternalImageUrl({
  required String imageUrl,
  required String? baseUrl,
  required int? port,
  required bool addPort,
}) {
  final uri = Uri.tryParse(imageUrl);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return false;
  }
  final server = Uri.tryParse(
    Endpoints.baseApi(
      baseUrl: baseUrl,
      port: port,
      addPort: addPort,
      appendApiToUrl: false,
    ),
  );
  if (server == null ||
      (server.scheme != 'http' && server.scheme != 'https') ||
      server.host.isEmpty) {
    return true;
  }
  return uri.origin != server.origin;
}
