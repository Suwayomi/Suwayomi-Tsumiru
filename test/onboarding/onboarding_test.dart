// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart' show ThemeMode;
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
  Future<SharedPreferences> seeded(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await seedFirstRunPreferences(sp);
    return sp;
  }

  test('first-run completion predicate and Dark theme seed', () async {
    // Migration predicate: unset / empty / default loopback are not configured.
    expect(serverConfiguredForOnboarding(null), isFalse);
    expect(serverConfiguredForOnboarding(''), isFalse);
    expect(serverConfiguredForOnboarding('http://127.0.0.1'), isFalse);

    // A fresh install defaults to false, so the wizard shows.
    final c = await _container({});
    expect(c.read(onboardingCompleteProvider) ?? false, isFalse);

    // A fresh install starts onboarding in Dark.
    var sp = await seeded({});
    expect(sp.getBool('onboardingComplete'), isFalse);
    expect(sp.getInt('themeMode'), ThemeMode.dark.index);

    // A saved mode is never overwritten.
    sp = await seeded({'themeMode': ThemeMode.light.index});
    expect(sp.getInt('themeMode'), ThemeMode.light.index);
  });
}
