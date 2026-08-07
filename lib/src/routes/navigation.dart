// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';

import 'router_config.dart';

/// Global search is a top-level route, so it covers the shell and its bottom
/// nav. It has to be pushed: `go` replaces the stack, leaving nothing to go
/// back to and no way off the screen but killing the app (#350). Routed
/// through here so no caller has to know that.
void openGlobalSearch(BuildContext context, {String? query}) =>
    GlobalSearchRoute(query: query).push(context);
