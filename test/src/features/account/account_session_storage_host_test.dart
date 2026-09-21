// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_session_storage.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/account/presentation/account_session_host.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_session_transition.dart';
import 'package:tsumiru/src/features/offline/data/account_catalogue_repository_io.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_paths.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_recovery_state.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_lock.dart';
import 'package:tsumiru/src/features/offline/data/offline_awaiting_server_downloads.dart';
import 'package:tsumiru/src/features/offline/data/offline_bootstrap.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:tsumiru/src/features/offline/presentation/account_storage_recovery_banner.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _Support extends PathProviderPlatform {
  _Support(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

const _a = AccountBinding(
  address: 'http://server',
  userId: 2,
  username: 'A',
  catalogId: 'A',
);
const _b = AccountBinding(
  address: 'http://server',
  userId: 3,
  username: 'B',
  catalogId: 'B',
);

class _Form extends StatefulWidget {
  const _Form({super.key, required this.changing});
  final bool changing;
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final controller = TextEditingController();
  String? error;
  void reject() => setState(() => error = 'Rejected request');
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Offstage(
        offstage: widget.changing,
        child: Column(
          children: [
            TextField(controller: controller),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
  );
}

class _Fixture {
  _Fixture(this.preferences);
  final SharedPreferences preferences;
  late ProviderContainer active;
  int restarts = 0;
  int retained = 0;
  Completer<void>? recoveryStarted;
  Completer<void>? recoveryRelease;

  ProviderContainer create() => ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      accountStorageOpenerProvider.overrideWithValue(({
        accountId,
        legacyInstanceId,
        ownedRoot,
        accountOwner,
        recovery,
      }) async {
        if (recovery != null && recoveryStarted != null) {
          recoveryStarted!.complete();
          await recoveryRelease!.future;
          recovery.check();
        }
        return initOfflineStorage(
          accountId: accountId,
          legacyInstanceId: legacyInstanceId,
          ownedRoot: ownedRoot,
          accountOwner: accountOwner,
          recovery: recovery,
        );
      }),
      currentServerAddressProvider.overrideWithValue('http://server'),
      offlineServerAccessProvider.overrideWithValue(false),
      authSessionTransitionProvider.overrideWith(
        (ref) => ref.read(accountSessionStorageProvider),
      ),
      serverInstanceIdProvider.overrideWith(
        (ref) async =>
            ref
                .watch(authCredentialsStoreProvider)
                .value
                ?.accountBinding
                ?.catalogId ??
            '',
      ),
    ],
  );

  static Future<_Fixture> open({
    bool legacy = false,
    bool partial = false,
  }) async {
    final root = await Directory.systemTemp.createTemp('session-storage-host-');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Support(root.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
    FlutterSecureStorage.setMockInitialValues({
      'auth.ui.accessToken': 'A-access',
      'auth.ui.refreshToken': 'A-refresh',
      'auth.ui.accountBinding': _a.encode(
        accessToken: 'A-access',
        refreshToken: 'A-refresh',
      ),
    });
    SharedPreferences.setMockInitialValues({
      DBKeys.authType.name: AuthType.uiLogin.index,
    });
    final fixture = _Fixture(await SharedPreferences.getInstance());
    if (legacy) {
      final storage = (await initOfflineStorage())!;
      await storage.db.upsertMangaMetadata(
        id: 1,
        title: 'Legacy',
        updatedAt: DateTime(2026),
      );
      final pages = Directory(p.join(storage.paths.baseDir, '1', '7'));
      await pages.create(recursive: true);
      await File(p.join(pages.path, '000.jpg')).writeAsBytes([1, 2, 3]);
      await storage.db.close();
      if (partial) {
        final destination = File(
          p.join(storage.paths.baseDir, 'accounts', 'A', 'catalog.sqlite'),
        );
        await destination.parent.create(recursive: true);
        await File(
          p.join(storage.paths.baseDir, 'catalog.sqlite'),
        ).copy(destination.path);
      }
      await fixture.preferences.setString(
        DBKeys.offlineCatalogServerId.name,
        'A',
      );
      await fixture.preferences.setInt(
        DBKeys.offlineCatchUpWatermark.name,
        123,
      );
      await fixture.preferences.setStringList(
        DBKeys.offlineCatchUpAwaitingPull.name,
        ['1'],
      );
    }
    fixture.active = fixture.create();
    await fixture.active.read(authCredentialsStoreProvider.future);
    await fixture.active.read(accountSessionStorageProvider).restore();
    fixture.active
        .read(authCredentialsStoreProvider.notifier)
        .activateSession();
    return fixture;
  }

  Widget host(GlobalKey<_FormState> form) => AccountSessionHost(
    initialContainer: active,
    sessionKey: (scope) {
      final state = scope.read(authCredentialsStoreProvider).requireValue;
      return (
        scope.read(authTypeKeyProvider),
        scope.read(currentServerAddressProvider),
        state.accountBinding,
        state.uiAccessToken,
        state.uiRefreshToken,
        state.simpleLoginCookie,
        scope.read(offlineRuntimeStorageProvider),
      );
    },
    onRetained: (scope) async {
      retained++;
      scope.read(authCredentialsStoreProvider.notifier).activateSession();
    },
    restart: (previous) async {
      restarts++;
      final storage = previous
          .read(offlineRuntimeStorageProvider.notifier)
          .take();
      final next = create();
      await next.read(authCredentialsStoreProvider.future);
      await next
          .read(offlineRuntimeStorageProvider.notifier)
          .replace(drain: () async {}, open: () async => storage);
      next.read(authCredentialsStoreProvider.notifier).activateSession();
      active = next;
      return next;
    },
    builder: (changing) => _Form(key: form, changing: changing),
    loading: const SizedBox(),
    errorBuilder: (error) => Text('Restart failed: $error'),
  );

  Future<void> close() => active
      .read(offlineRuntimeStorageProvider.notifier)
      .replace(drain: () async {}, open: () async => null);
}

Future<void> _settleHost(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  testWidgets(
    'recovery lock timeout shows Retry and succeeds after the worker releases',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = await _Fixture.open(legacy: true, partial: true);
        final support = await PathProviderPlatform.instance
            .getApplicationSupportPath();
        final lock = BackgroundDownloadLock(
          File(p.join(support!, 'offline', '.bg_lock')),
        );
        expect(await lock.acquire('blocked-worker'), isTrue);
        addTearDown(lock.release);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.active,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: AccountStorageRecoveryBanner()),
            ),
          ),
        );
        final elapsed = Stopwatch()..start();
        await fixture.active
            .read(accountSessionStorageProvider)
            .recover()
            .timeout(const Duration(seconds: 45));
        expect(
          elapsed.elapsed,
          greaterThanOrEqualTo(const Duration(seconds: 30)),
        );
        expect(
          fixture.active.read(accountStorageRecoveryProvider)?.phase,
          AccountStorageRecoveryPhase.failed,
        );
        expect(fixture.active.read(offlineRuntimeStorageProvider), isNull);
        expect(await lock.yieldRequested(), isTrue);
        await tester.pump();
        expect(find.text('Retry'), findsOneWidget);
        await lock.release();
        await tester.tap(find.text('Retry'));
        for (
          var attempt = 0;
          attempt < 100 &&
              fixture.active.read(accountStorageRecoveryProvider) != null;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        expect(fixture.active.read(accountStorageRecoveryProvider), isNull);
        final storage = fixture.active.read(offlineRuntimeStorageProvider)!;
        expect((await storage.db.mangaById(1))?.title, 'Legacy');
        expect(
          await File(
            p.join(storage.paths.baseDir, '1', '7', '000.jpg'),
          ).readAsBytes(),
          [1, 2, 3],
        );
        expect(find.text('Retry'), findsNothing);
        await fixture.close();
        await tester.pumpWidget(const SizedBox());
        fixture.active.dispose();
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'sign-out cancels pending recovery without reopening its catalogue',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = await _Fixture.open(legacy: true, partial: true);
        fixture.recoveryStarted = Completer<void>();
        fixture.recoveryRelease = Completer<void>();
        final recovery = fixture.active
            .read(accountSessionStorageProvider)
            .recover();
        await fixture.recoveryStarted!.future;
        final credentials = fixture.active.read(
          authCredentialsStoreProvider.notifier,
        );
        final signOut = credentials.withIdentityChange(
          credentials.clearUiLoginTokens,
        );
        fixture.recoveryRelease!.complete();
        await Future.wait([recovery, signOut]);
        expect(fixture.active.read(offlineRuntimeStorageProvider), isNull);
        expect(fixture.active.read(accountStorageRecoveryProvider), isNull);
        expect(fixture.active.read(offlineEnabledProvider), isFalse);
        await fixture.close();
        fixture.active.dispose();
      });
    },
  );

  testWidgets('partial upgrade opens the app before recovering its downloads', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final fixture = await _Fixture.open(legacy: true, partial: true);
      await tester.pumpWidget(fixture.host(GlobalKey<_FormState>()));
      expect(find.byType(TextField), findsOneWidget);
      expect(fixture.active.read(offlineRuntimeStorageProvider), isNull);
      expect(
        fixture.active.read(accountStorageRecoveryProvider)?.phase,
        AccountStorageRecoveryPhase.pending,
      );
      await fixture.active.read(accountSessionStorageProvider).recover();
      final storage = fixture.active.read(offlineRuntimeStorageProvider)!;
      expect((await storage.db.mangaById(1))?.title, 'Legacy');
      expect(
        await File(
          p.join(storage.paths.baseDir, '1', '7', '000.jpg'),
        ).readAsBytes(),
        [1, 2, 3],
      );
      expect(fixture.active.read(accountStorageRecoveryProvider), isNull);
      expect(fixture.restarts, 0);
      await fixture.close();
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'removed legacy files and preferences stay empty after full account restore',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = await _Fixture.open(legacy: true);
        await tester.pumpWidget(fixture.host(GlobalKey<_FormState>()));
        final before = fixture.active.read(offlineRuntimeStorageProvider)!;
        final root = offlineControlRoot(before.paths.baseDir);
        expect(before.paths.baseDir, root);
        expect(fixture.preferences.getBool(offlineAccountScopedKey), isFalse);
        final watermark = '${DBKeys.offlineCatchUpWatermark.name}/A';
        final awaiting = '${DBKeys.offlineCatchUpAwaitingPull.name}/A';
        expect((await before.db.mangaById(1))!.title, 'Legacy');
        expect(fixture.preferences.getInt(watermark), 123);
        expect(fixture.preferences.getStringList(awaiting), ['1']);
        var credentials = fixture.active.read(
          authCredentialsStoreProvider.notifier,
        );
        await credentials.withIdentityChange(credentials.clearUiLoginTokens);
        await _settleHost(tester);
        expect(fixture.active.read(offlineRuntimeStorageProvider), isNull);
        credentials = fixture.active.read(
          authCredentialsStoreProvider.notifier,
        );
        await credentials.withIdentityChange(() async {
          fixture.active
              .read(authTypeKeyProvider.notifier)
              .update(AuthType.none);
        });
        await _settleHost(tester);
        expect(fixture.active.read(offlineRuntimeStorageProvider), isNull);
        expect(fixture.preferences.getBool(offlineAccountScopedKey), isFalse);
        final repository = NativeAccountCatalogueRepository(
          root,
          fixture.preferences,
        );
        await repository.remove(
          (await repository.list()).single,
          canRemove: () => true,
        );
        credentials = fixture.active.read(
          authCredentialsStoreProvider.notifier,
        );
        await credentials.withIdentityChange(() async {
          fixture.active
              .read(authTypeKeyProvider.notifier)
              .update(AuthType.uiLogin);
          await credentials.saveUiLoginTokens(
            accessToken: 'return-access',
            refreshToken: 'return-refresh',
            binding: _a,
          );
        });
        await _settleHost(tester);
        final after = fixture.active.read(offlineRuntimeStorageProvider)!;
        expect(after.paths.baseDir, root);
        expect(fixture.preferences.getBool(offlineAccountScopedKey), isFalse);
        expect(await after.db.mangaById(1), isNull);
        expect(
          await Directory(p.join(after.paths.baseDir, '1')).exists(),
          isFalse,
        );
        expect(fixture.preferences.getInt(watermark), isNull);
        expect(fixture.preferences.getStringList(awaiting), isNull);
        expect(
          fixture.preferences.getInt(DBKeys.offlineCatchUpWatermark.name),
          123,
        );
        expect(
          fixture.preferences.getStringList(
            DBKeys.offlineCatchUpAwaitingPull.name,
          ),
          ['1'],
        );
        await after.db.upsertMangaMetadata(
          id: 2,
          title: 'New',
          updatedAt: DateTime(2026),
        );
        await fixture.preferences.setInt(
          offlinePreferenceKey(
            fixture.active.read,
            DBKeys.offlineCatchUpWatermark,
          ),
          456,
        );
        awaitingServerDownloads.add(2);
        await persistAwaitingServerDownloads(fixture.active.read);
        awaitingServerDownloads.clear();
        expect((await after.db.mangaById(2))!.title, 'New');
        expect(fixture.preferences.getInt(watermark), 456);
        expect(fixture.preferences.getStringList(awaiting), ['2']);
        await fixture.close();
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'rejected native account action retains the form, error and open database',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = await _Fixture.open();
        final before = fixture.active.read(offlineRuntimeStorageProvider)!;
        await before.db.upsertMangaMetadata(
          id: 1,
          title: 'A private title',
          updatedAt: DateTime(2026),
        );
        final form = GlobalKey<_FormState>();
        await tester.pumpWidget(fixture.host(form));
        final originalForm = form.currentState;
        await tester.enterText(find.byType(TextField), 'draft input');
        await expectLater(
          fixture.active
              .read(authCredentialsStoreProvider.notifier)
              .withIdentityChange<void>(() async {
                throw StateError('rejected');
              }),
          throwsStateError,
        );
        form.currentState!.reject();
        await _settleHost(tester);
        expect(fixture.restarts, 0);
        expect(fixture.retained, 1);
        expect(form.currentState, same(originalForm));
        expect(find.text('draft input'), findsOneWidget);
        expect(find.text('Rejected request'), findsOneWidget);
        expect(
          fixture.active.read(offlineRuntimeStorageProvider),
          same(before),
        );
        expect((await before.db.mangaById(1))!.title, 'A private title');
        await fixture.close();
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'successful same-account credentials replace the form but transfer the same open database',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = await _Fixture.open();
        final before = fixture.active.read(offlineRuntimeStorageProvider)!;
        final originalContainer = fixture.active;
        await before.db.upsertMangaMetadata(
          id: 1,
          title: 'Preserved',
          updatedAt: DateTime(2026),
        );
        final form = GlobalKey<_FormState>();
        await tester.pumpWidget(fixture.host(form));
        final originalForm = form.currentState;
        await tester.enterText(find.byType(TextField), 'old password draft');
        await fixture.active
            .read(authCredentialsStoreProvider.notifier)
            .saveUiLoginTokens(
              accessToken: 'new-A-access',
              refreshToken: 'new-A-refresh',
              binding: _a,
            );
        await _settleHost(tester);
        expect(fixture.restarts, 1);
        expect(fixture.active, isNot(same(originalContainer)));
        expect(form.currentState, isNot(same(originalForm)));
        expect(find.text('old password draft'), findsNothing);
        expect(
          fixture.active.read(offlineRuntimeStorageProvider),
          same(before),
        );
        expect(
          fixture.active
              .read(authCredentialsStoreProvider)
              .requireValue
              .uiAccessToken,
          'new-A-access',
        );
        expect((await before.db.mangaById(1))!.title, 'Preserved');
        await fixture.close();
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'owner changed before an action throws still closes A and opens B',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = await _Fixture.open();
        final before = fixture.active.read(offlineRuntimeStorageProvider)!;
        await before.db.upsertMangaMetadata(
          id: 1,
          title: 'A only',
          updatedAt: DateTime(2026),
        );
        await tester.pumpWidget(fixture.host(GlobalKey<_FormState>()));
        final store = fixture.active.read(
          authCredentialsStoreProvider.notifier,
        );
        await expectLater(
          store.withIdentityChange<void>(() async {
            await store.saveUiLoginTokens(
              accessToken: 'B-access',
              refreshToken: 'B-refresh',
              binding: _b,
            );
            throw StateError('failure after adoption');
          }),
          throwsStateError,
        );
        await _settleHost(tester);
        final after = fixture.active.read(offlineRuntimeStorageProvider)!;
        expect(fixture.restarts, 1);
        expect(after, isNot(same(before)));
        expect(after.paths.baseDir, endsWith('/accounts/B'));
        expect(await after.db.mangaById(1), isNull);
        await expectLater(before.db.mangaById(1), throwsStateError);
        expect(
          File('${before.paths.baseDir}/catalog.sqlite').existsSync(),
          isTrue,
        );
        await fixture.close();
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
}
