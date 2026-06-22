// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'force_portrait_tile.g.dart';

@riverpod
class ForcePortrait extends _$ForcePortrait with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.forcePortrait);
}

/// Apply the portrait-lock preference to the system. Only phones honour it
/// (landscape on a phone currently renders poorly); tablets, desktop and web
/// always keep every orientation regardless of the setting.
void applyForcePortrait(bool forcePortrait) {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  final shortestSide = views.isEmpty
      ? 0.0
      : (views.first.physicalSize / views.first.devicePixelRatio).shortestSide;
  final isPhone = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      shortestSide > 0 &&
      shortestSide < 600;
  SystemChrome.setPreferredOrientations(
    forcePortrait && isPhone
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : DeviceOrientation.values,
  );
}

class ForcePortraitTile extends ConsumerWidget {
  const ForcePortraitTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: const Icon(Icons.screen_lock_portrait_rounded),
      title: const Text('Lock to portrait'),
      subtitle: const Text('Stop the app rotating to landscape on phones'),
      onChanged: (value) {
        ref.read(forcePortraitProvider.notifier).update(value);
        applyForcePortrait(value);
      },
      value: ref.watch(forcePortraitProvider).ifNull(),
    );
  }
}
