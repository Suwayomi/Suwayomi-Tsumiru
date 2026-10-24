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

/// False redirects every route to /onboarding; persisted across launches.
@riverpod
class OnboardingComplete extends _$OnboardingComplete
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.onboardingComplete);
}

/// A nonempty, non-default-loopback URL counts as an existing configuration.
bool serverConfiguredForOnboarding(String? serverUrl) =>
    serverUrl != null &&
    serverUrl.isNotEmpty &&
    serverUrl != DBKeys.serverUrl.initial;

/// Seeds only unset onboarding state; new installs default to Dark unless a theme is saved.
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
