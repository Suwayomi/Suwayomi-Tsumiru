// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'onboarding_complete.g.dart';

/// Whether the first-time onboarding wizard has been finished. While false, the
/// router sends every route to `/onboarding`. Persisted in SharedPreferences;
/// a one-time launch migration seeds it true for already-configured installs.
@riverpod
class OnboardingComplete extends _$OnboardingComplete
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.onboardingComplete);
}

/// Whether a saved server URL counts as "already configured" for the one-time
/// onboarding migration — anything but unset/empty or the default loopback.
/// Existing installs that pass this are seeded onboarded so the wizard never
/// shows for them.
bool serverConfiguredForOnboarding(String? serverUrl) =>
    serverUrl != null &&
    serverUrl.isNotEmpty &&
    serverUrl != DBKeys.serverUrl.initial;

/// One-time first-run seeding, run at launch while [DBKeys.onboardingComplete]
/// is unset. Installs with a real server skip the wizard; genuinely new ones
/// also start in Dark unless a theme mode is already stored, so existing
/// users keep following the system.
Future<void> seedFirstRunPreferences(SharedPreferences prefs) async {
  if (prefs.getBool(DBKeys.onboardingComplete.name) != null) return;
  final configured = serverConfiguredForOnboarding(
    prefs.getString(DBKeys.serverUrl.name),
  );
  await prefs.setBool(DBKeys.onboardingComplete.name, configured);
  if (!configured && !prefs.containsKey(DBKeys.themeMode.name)) {
    await prefs.setInt(DBKeys.themeMode.name, ThemeMode.dark.index);
  }
}
