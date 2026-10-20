// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_repository/extension_repository.dart';
import 'package:tsumiru/src/features/browse_center/data/source_repository/source_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_actions.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../../helpers/fake_extension_repository.dart';
import '../../../../../helpers/legacy_account_access.dart';

class _CountingSourceRepository extends SourceRepository {
  _CountingSourceRepository()
    : super(dummyGraphQLClient(), permissions: legacyAccountPermissions);

  int listCalls = 0;

  @override
  Future<List<SourceDto>?> getSourceList() async {
    listCalls++;
    return <SourceDto>[];
  }
}

void main() {
  late FakeExtensionRepository extensions;
  late _CountingSourceRepository sources;
  late ProviderContainer container;

  setUp(() async {
    extensions = FakeExtensionRepository();
    sources = _CountingSourceRepository();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    container = ProviderContainer(
      overrides: [
        settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
        authCredentialsStoreProvider.overrideWith(ActionTestCredentials.new),
        extensionRepositoryProvider.overrideWithValue(extensions),
        sourceRepositoryProvider.overrideWithValue(sources),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    // Browse keeps the Sources tab alive behind the Extensions tab, so the
    // source list holds a listener for the whole session. That's what made the
    // stale list survive every tab switch (#344).
    container.listen(sourceListProvider, (previous, next) {});
    container.listen(sourceLanguageFilterProvider, (previous, next) {});
  });

  tearDown(() => container.dispose());

  Future<int> sourceFetchesAfter(Future<void> Function() action) async {
    await container.read(sourceListProvider.future);
    final before = sources.listCalls;
    await action();
    await container.read(sourceListProvider.future);
    return sources.listCalls - before;
  }

  test('reinstalling removes the extension before putting it back', () async {
    final actions = container.read(extensionActionsProvider);
    final refetches = await sourceFetchesAfter(
      () => actions.reinstall('com.example.ext'),
    );

    expect(extensions.calls, <String>[
      'uninstall com.example.ext',
      'install com.example.ext',
    ]);
    expect(
      refetches,
      1,
      reason: 'the rebuilt extension re-registers its sources server-side',
    );
  });
}

class ActionTestCredentials extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}
