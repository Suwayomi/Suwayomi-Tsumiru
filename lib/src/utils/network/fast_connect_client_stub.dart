// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:http/http.dart' as http;

/// Web: the browser owns connection handling; no connect timeout to set.
http.Client createFastConnectClient(Duration connectionTimeout) =>
    http.Client();
