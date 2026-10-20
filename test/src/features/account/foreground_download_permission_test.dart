import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_permission.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../../../helpers/offline_test_db.dart';
import 'account_providers_test.dart' show FakeAccountRepository;

const _binding = AccountBinding(
  address: 'http://server',
  userId: 2,
  username: 'reader',
  catalogId: 'A',
);

class _Credentials extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState(
    accountBinding: _binding,
    uiAccessToken: 'access',
    uiRefreshToken: 'refresh',
  );
}

Fragment$AccountDto _user(bool allowed) => Fragment$AccountDto(
  id: 2,
  username: 'reader',
  permissions: [if (allowed) Enum$UserPermission.DOWNLOAD_CHAPTERS],
  roles: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    root = await Directory.systemTemp.createTemp('foreground-permission-');
  });

  Future<ProviderContainer> setup(FakeAccountRepository repository) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authTypeKeyProvider.overrideWithValue(AuthType.uiLogin),
        authCredentialsStoreProvider.overrideWith(_Credentials.new),
        accountRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final paths = OfflinePaths(root.path);
    await container.read(authCredentialsStoreProvider.future);
    container.read(authCredentialsStoreProvider.notifier).activateSession();
    await container
        .read(offlineRuntimeStorageProvider.notifier)
        .replace(
          drain: () async {},
          open: () async => (
            db: testOfflineDatabase(),
            paths: paths,
            store: IoOfflinePageStore(paths),
          ),
        );
    addTearDown(() async {
      await container
          .read(offlineRuntimeStorageProvider.notifier)
          .replace(drain: () async {}, open: () async => null);
      container.dispose();
    });
    return container;
  }

  for (final allowed in [true, false]) {
    test('fresh account publication records download grant $allowed', () async {
      final container = await setup(
        FakeAccountRepository(user: _user(allowed)),
      );
      final result = verifyDownloadPermission(container.read);
      if (allowed) {
        await result;
      } else {
        await expectLater(result, throwsA(isA<AccountPermissionDenied>()));
      }
      final state = CatchupStateStore(preferences);
      expect(downloadPermissionAllowed(container.read), allowed);
      expect(state.downloadPermissionPaused('A'), !allowed);
      expect(preferences.getString('account.current/A'), isNotNull);
    });
  }

}
