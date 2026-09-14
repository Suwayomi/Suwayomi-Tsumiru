// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_repository/extension_repository.dart';
import 'package:tsumiru/src/features/browse_center/data/source_repository/source_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/extension/extension_model.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_actions.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

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

  for (final permission in [
    Enum$UserPermission.INSTALL_EXTENSIONS,
    Enum$UserPermission.UNINSTALL_EXTENSIONS,
  ]) {
    test(
      'reinstall with only $permission never partially uninstalls',
      () async {
        final access = AccountAccess(
          capability: AccountCapability.supported,
          user: Fragment$AccountDto(
            id: 2,
            username: 'reader',
            permissions: [permission],
            roles: [Enum$UserRole.USER],
          ),
        );
        final restricted = FakeExtensionRepository(
          permissions: AccountPermissionGuard(() => access),
        );
        container.updateOverrides([
          settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
          authCredentialsStoreProvider.overrideWith(ActionTestCredentials.new),
          extensionRepositoryProvider.overrideWithValue(restricted),
          sourceRepositoryProvider.overrideWithValue(sources),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ]);
        await expectLater(
          container.read(extensionActionsProvider).reinstall('pkg'),
          throwsA(isA<AccountPermissionDenied>()),
        );
        expect(restricted.calls, isEmpty);
      },
    );
  }

  test(
    'identity change during reinstall prevents installation and language updates',
    () async {
      final delayed = DelayedUninstallRepository();
      container.updateOverrides([
        settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
        authCredentialsStoreProvider.overrideWith(ActionTestCredentials.new),
        extensionRepositoryProvider.overrideWithValue(delayed),
        sourceRepositoryProvider.overrideWithValue(sources),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ]);
      await container.read(authCredentialsStoreProvider.future);
      final languages = container.read(sourceLanguageFilterProvider);
      final work = container
          .read(extensionActionsProvider)
          .reinstall('pkg', languageCode: 'fr');
      await delayed.entered.future;
      await container
          .read(authCredentialsStoreProvider.notifier)
          .withIdentityChange(() async {});
      delayed.release.complete();
      await work;
      expect(delayed.installed, isEmpty);
      expect(delayed.calls, ['uninstall pkg']);
      expect(container.read(sourceLanguageFilterProvider), languages);
    },
  );

  tearDown(() => container.dispose());

  Future<int> sourceFetchesAfter(Future<void> Function() action) async {
    await container.read(sourceListProvider.future);
    final before = sources.listCalls;
    await action();
    await container.read(sourceListProvider.future);
    return sources.listCalls - before;
  }

  Future<int> badgeCountsAfter(Future<void> Function() action) async {
    container.listen(extensionUpdateBadgeCountProvider, (previous, next) {});
    await container.read(extensionUpdateBadgeCountProvider.future);
    final before = extensions.updateCountCalls;
    await action();
    await container.read(extensionUpdateBadgeCountProvider.future);
    return extensions.updateCountCalls - before;
  }

  test('updating an extension recounts the Browse badge', () async {
    final actions = container.read(extensionActionsProvider);
    expect(await badgeCountsAfter(() => actions.update('com.example.ext')), 1);
  });

  test('refreshing the extension list recounts the Browse badge', () async {
    final actions = container.read(extensionActionsProvider);
    expect(await badgeCountsAfter(actions.refreshList), 1);
  });

  test('installing an extension refetches the source list', () async {
    final actions = container.read(extensionActionsProvider);
    final refetches = await sourceFetchesAfter(
      () => actions.install('com.example.ext'),
    );

    expect(extensions.installed, <String>['com.example.ext']);
    expect(
      refetches,
      1,
      reason: 'the installed extension registers new sources server-side',
    );
  });

  test('uninstalling an extension refetches the source list', () async {
    final actions = container.read(extensionActionsProvider);
    final refetches = await sourceFetchesAfter(
      () => actions.uninstall('com.example.ext'),
    );

    expect(extensions.uninstalled, <String>['com.example.ext']);
    expect(
      refetches,
      1,
      reason: "the removed extension's sources have to disappear too",
    );
  });

  test('updating an extension refetches the source list', () async {
    final actions = container.read(extensionActionsProvider);
    final refetches = await sourceFetchesAfter(
      () => actions.update('com.example.ext'),
    );

    expect(extensions.updated, <String>['com.example.ext']);
    expect(
      refetches,
      1,
      reason: 'an update can add or drop sources within the extension',
    );
  });

  test(
    "installing enables the extension's language in the source filter",
    () async {
      expect(
        container.read(sourceLanguageFilterProvider),
        isNot(contains('ko')),
      );

      await container
          .read(extensionActionsProvider)
          .install('com.example.ext', languageCode: 'ko');

      expect(container.read(sourceLanguageFilterProvider), contains('ko'));
    },
  );

  test('installing leaves an emptied language filter empty', () async {
    container.read(sourceLanguageFilterProvider.notifier).update(<String>[]);

    await container
        .read(extensionActionsProvider)
        .install('com.example.ext', languageCode: 'ko');

    expect(container.read(sourceLanguageFilterProvider), isEmpty);
  });

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

  test(
    "reinstalling enables the extension's language in the source filter",
    () async {
      expect(
        container.read(sourceLanguageFilterProvider),
        isNot(contains('ko')),
      );

      await container
          .read(extensionActionsProvider)
          .reinstall('com.example.ext', languageCode: 'ko');

      expect(container.read(sourceLanguageFilterProvider), contains('ko'));
    },
  );

  test('a failed install leaves the source list alone', () async {
    final failing = ProviderContainer(
      overrides: [
        settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
        authCredentialsStoreProvider.overrideWith(ActionTestCredentials.new),
        extensionRepositoryProvider.overrideWithValue(_ThrowingRepository()),
        sourceRepositoryProvider.overrideWithValue(sources),
      ],
    );
    addTearDown(failing.dispose);
    failing.listen(sourceListProvider, (previous, next) {});
    await failing.read(sourceListProvider.future);
    final before = sources.listCalls;

    await expectLater(
      failing.read(extensionActionsProvider).install('com.example.ext'),
      throwsA(isA<Exception>()),
    );

    expect(sources.listCalls, before);
  });

  testWidgets('installing from a file refetches the source list', (
    tester,
  ) async {
    // Only a BuildContext to hand to the picker call. The container stays
    // detached from the tree: attaching it makes Riverpod defer refreshes to a
    // frame that a bare `await` never pumps.
    final apk = _FakeApk();
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // runAsync puts this on the real event loop. The widget tester's fake clock
    // never advances the timers the container refreshes on, so a bare await here
    // waits forever.
    await tester.runAsync(() async {
      await container.read(sourceListProvider.future);
      final before = sources.listCalls;

      await container
          .read(extensionActionsProvider)
          .installFile(capturedContext, file: apk);
      await container.read(sourceListProvider.future);

      expect(extensions.fileInstalls.single.name, 'source.apk');
      expect(sources.listCalls, before + 1);
    });
  });
}

class _ThrowingRepository extends ExtensionRepository {
  _ThrowingRepository()
    : super(dummyGraphQLClient(), permissions: legacyAccountPermissions);

  @override
  Future<void> installExtension(String pkgName) async =>
      throw Exception('install failed');

  @override
  Future<List<Extension>?> getExtensionListStream() async => <Extension>[];
}

base class _FakeApk extends PlatformFile {
  @override
  String get name => 'source.apk';
  @override
  Uri get uri => Uri.file('/tmp/source.apk');
  @override
  XFile get xFile => XFile(uri.toFilePath());
  @override
  int? lengthSync() => 4;
  @override
  Future<int> length() async => 4;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List(4);
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(Uint8List(4));
}

class DelayedUninstallRepository extends FakeExtensionRepository {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> uninstallExtension(String pkgName) async {
    await super.uninstallExtension(pkgName);
    entered.complete();
    await release.future;
  }
}

class ActionTestCredentials extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}
