// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
  test('offlineSync is null when offline is disabled (default / web)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(offlineSyncProvider), isNull);
  });

  test('offlineSync is provided when offline is enabled', () {
    final db = testOfflineDatabase();
    final container = ProviderContainer(overrides: [
      offlineEnabledProvider.overrideWithValue(true),
      offlineDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(() {
      container.dispose();
      db.close();
    });
    expect(container.read(offlineSyncProvider), isNotNull);
  });
}
