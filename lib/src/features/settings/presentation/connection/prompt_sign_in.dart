// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../routes/router_config.dart';

/// Keeps you on Connection across an identity change.
///
/// Changing the server address, changing the auth mode and signing out all
/// swap the session container, which rebuilds the router at its initial
/// location. That drops you on an unauthorized Library, away from the screen
/// you were working on and away from sign-in.
///
/// Showing a dialog instead does not survive it: the screen that owns the
/// dialog's context is disposed by the same swap. Handing the destination to
/// the rebuilt router is the only thing the rebuild cannot overwrite.
void stayOnConnectionAfterIdentityChange() {
  routeAfterIdentityChange(const ConnectionRoute().location);
}
