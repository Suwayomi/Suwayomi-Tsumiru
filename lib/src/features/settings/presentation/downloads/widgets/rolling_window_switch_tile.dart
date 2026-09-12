// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../data/delete_chapters_settings_repository.dart';

/// The "Rolling download window" toggle. Backed by [localRollingWindowProvider],
/// so this single widget can be shown in both the on-device downloads settings
/// and the reader settings screen — the same option, one source of truth, not a
/// duplicated control.
class RollingWindowSwitchTile extends ConsumerWidget {
  const RollingWindowSwitchTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(context.l10n.rollingWindowTitle),
      subtitle: Text(context.l10n.rollingWindowDescription),
      value: ref.watch(localRollingWindowProvider) ?? false,
      onChanged: (v) async =>
          ref.read(localRollingWindowProvider.notifier).update(v),
    );
  }
}
