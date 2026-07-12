// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/settings/presentation/library/widgets/show_update_progress_banner/show_update_progress_banner.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  group('showUpdateProgressBannerProvider', () {
    test('defaults to on', () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(showUpdateProgressBannerProvider), isTrue);
    });

    test('update persists the flag', () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      container.read(showUpdateProgressBannerProvider.notifier).update(false);
      expect(container.read(showUpdateProgressBannerProvider), isFalse);
      expect(prefs.getBool('showUpdateProgressBanner'), isFalse);
    });
  });
}
