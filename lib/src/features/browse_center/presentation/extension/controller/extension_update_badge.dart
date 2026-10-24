// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../offline/data/server_reachability.dart';
import '../../../data/extension_repository/extension_repository.dart';

part 'extension_update_badge.g.dart';

@riverpod
Future<int> extensionUpdateBadgeCount(Ref ref) async {
  if (ref.watch(serverUnreachableProvider)) return 0;
  try {
    return await ref
        .watch(extensionRepositoryProvider)
        .getExtensionUpdateCount();
  } catch (_) {
    return 0;
  }
}
