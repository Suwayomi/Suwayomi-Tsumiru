// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_types.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  test('safetyNetConfigProvider defaults to off', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    expect(c.read(safetyNetConfigProvider).storageCapEnabled, false);
    expect(c.read(safetyNetConfigProvider).timeEvictEnabled, false);
  });
}
