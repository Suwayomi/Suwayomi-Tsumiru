// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/onboarding/data/onboarding_complete.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

Future<ProviderContainer> _container(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('serverConfiguredForOnboarding (migration predicate)', () {
    test('unset / empty / default loopback → not configured', () {
      expect(serverConfiguredForOnboarding(null), isFalse);
      expect(serverConfiguredForOnboarding(''), isFalse);
      expect(serverConfiguredForOnboarding('http://127.0.0.1'), isFalse);
    });

    test('a real server URL → configured (existing installs skip the wizard)',
        () {
      expect(serverConfiguredForOnboarding('http://192.168.0.10:4567'), isTrue);
      expect(
          serverConfiguredForOnboarding('https://suwayomi.example.com'), isTrue);
    });
  });

  group('onboardingCompleteProvider', () {
    test('defaults to false on a fresh install (so the wizard shows)', () async {
      final c = await _container({});
      expect(c.read(onboardingCompleteProvider) ?? false, isFalse);
    });

    test('reads a persisted true (finished / migrated installs skip it)',
        () async {
      final c = await _container({'flutter.onboardingComplete': true});
      expect(c.read(onboardingCompleteProvider), isTrue);
    });
  });
}
