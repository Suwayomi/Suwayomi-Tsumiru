// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// In a browser the cookie jar is the session: `Set-Cookie` is a forbidden
/// response header, so nothing can read it, and the browser sends it back on
/// its own. This is how Suwayomi's own WebUI signs in — it has no login code
/// at all, it just lets the server's form set the session cookie.
const browserManagesSession = true;

/// `withCredentials` so the cookie is stored and returned when the app is
/// served from a different origin than the server.
http.Client makeSimpleLoginClient() => BrowserClient()..withCredentials = true;
