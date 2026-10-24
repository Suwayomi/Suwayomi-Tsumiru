// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../global_providers/global_providers.dart';
import '../../offline/data/background/background_download_controller_shim.dart';

/// Saves the final step before sign-in can replace the wizard; rejection preserves onboarding state.
Future<void> finishOnboardingSignIn(
  WidgetRef ref,
  Future<void> Function() signIn,
) async {
  final preferences = ref.read(sharedPreferencesProvider);
  await ref.read(backgroundDownloadControllerProvider).changeIdentity(() async {
    await signIn();
    await preferences.setInt('onboarding.step', 2);
    await preferences.setString('onboarding.pendingProbe', '');
    await preferences.setBool('onboarding.advanceAfterProbe', false);
  });
}
