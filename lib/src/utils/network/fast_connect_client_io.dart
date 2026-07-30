// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// HTTP client whose CONNECT phase fails fast. The per-request timeout exists
/// for servers slow to answer, but a connection that can't even be established
/// in [connectionTimeout] is dead — waiting the full request window (and its
/// retries) on it is what made a dead network mean minutes of spinner.
http.Client createFastConnectClient(Duration connectionTimeout) =>
    IOClient(HttpClient()..connectionTimeout = connectionTimeout);
