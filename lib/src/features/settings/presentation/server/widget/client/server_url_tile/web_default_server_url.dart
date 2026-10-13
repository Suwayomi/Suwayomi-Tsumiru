// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Default server URL for the hosted web build: the page origin plus the
/// app's base path.
///
/// [baseUri] is the document's effective base URI (`document.baseURI`),
/// which honours the first `<base href>` — the server injects
/// `<base href="/tsumiru/">` ahead of Flutter's own when it serves the app
/// under a sub-path. Because this is the *base* URI and not the page URL, a
/// deep link can never leak its route into the result: on page
/// `http://h:4600/tsumiru/library` the base URI is still
/// `http://h:4600/tsumiru/`.
///
/// Pure over a string so it stays unit-testable without a browser; the
/// web-only reader (see `hosted_base_uri.dart`) supplies the input.
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
