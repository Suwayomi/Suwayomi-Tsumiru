// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Search-harness server stubs: settings-search entries watch the same
// server-backed providers their screens do, and search evaluates every
// entry's visibility on each keystroke. These test containers have no
// server, so a bare watch would error and leave Riverpod's retry timer
// pending at teardown. Stubbing them to resolved-but-empty
// (unreachable/unsupported) hides every server-gated entry without changing
// what the search tests assert.

import 'package:hooks_riverpod/misc.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/domain/koreader_sync_domain.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/web_interface_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';

class NoServerSettings extends Settings {
  @override
  Future<SettingsDto?> build() async => null;
}

/// Overrides that resolve every server-backed settings-search dependency to
/// unreachable/unsupported. Spread into a search test container's overrides.
List<Override> get unreachableServerStubs => [
  settingsProvider.overrideWith(NoServerSettings.new),
  webInterfaceSettingsProvider.overrideWith((ref) async => null),
  syncYomiSettingsProvider.overrideWith((ref) async => null),
  koreaderSyncSettingsProvider.overrideWith((ref) async => null),
  koSyncStatusProvider.overrideWith(
    (ref) async => const KoSyncStatus(isLoggedIn: false),
  ),
];
