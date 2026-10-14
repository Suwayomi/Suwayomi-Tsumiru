// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// The page origin and app base path.
String webDefaultServerUrl(String baseUri) {
  final uri = Uri.tryParse(baseUri.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return baseUri;
  var path = uri.path;
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isEmpty || path == '/') return uri.origin;
  return '${uri.origin}$path';
}
