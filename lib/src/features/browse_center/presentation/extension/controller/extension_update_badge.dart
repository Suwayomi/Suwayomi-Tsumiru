// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../offline/data/server_reachability.dart';
import '../../../data/extension_repository/extension_repository.dart';

part 'extension_update_badge.g.dart';

/// How many installed extensions have an update waiting, for the Browse nav
/// badge (Mihon/Komikku do the same, `HomeScreen.kt`).
///
/// Extension updates were only discoverable by opening Browse and noticing a
/// section, so people ran old extensions without knowing. A notification for
/// this exists but is off by default and is a heavier interruption than a
/// number on a tab.
///
/// Kept deliberately cheap: one count query, and none at all while the server
/// is unreachable. The nav shell is built on every launch, so anything
/// expensive here is paid constantly and by everyone.
@riverpod
Future<int> extensionUpdateBadgeCount(Ref ref) async {
  if (ref.watch(serverUnreachableProvider)) return 0;
  try {
    return await ref
        .watch(extensionRepositoryProvider)
        .getExtensionUpdateCount();
  } catch (_) {
    // A badge is not worth surfacing an error for; it simply doesn't show.
    return 0;
  }
}
