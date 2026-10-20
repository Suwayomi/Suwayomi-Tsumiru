import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/account_catalogue.dart';
import 'package:tsumiru/src/features/offline/data/account_catalogue_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

const _catalogue = AccountCatalogue(
  id: 'A',
  owner: '2',
  path: '/offline/accounts/A',
  bytes: 2048,
  username: 'reader',
  address: 'https://server.example',
);

class _Repository implements AccountCatalogueRepository {
  AccountCatalogue row = _catalogue;
  int removals = 0;
  Completer<void>? started;
  Completer<void>? release;
  @override
  Future<List<AccountCatalogue>> list({String? activePath}) async =>
      removals == 0 ? [row] : [];
  @override
  Future<void> remove(
    AccountCatalogue catalogue, {
    required bool Function() canRemove,
  }) async {
    if (!canRemove()) throw StateError('Catalogue is active');
    expect(identical(catalogue, row), isTrue);
    started?.complete();
    await release?.future;
    removals++;
  }
}

void main() {
  Future<ProviderContainer> container(
    _Repository repository, {
    bool active = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final binding = const AccountBinding(
      address: 'https://server.example',
      userId: 2,
      username: 'reader',
      catalogId: 'A',
    );
    FlutterSecureStorage.setMockInitialValues(
      active
          ? {
              'auth.ui.accessToken': 'access',
              'auth.ui.refreshToken': 'refresh',
              'auth.ui.accountBinding': binding.encode(
                accessToken: 'access',
                refreshToken: 'refresh',
              ),
            }
          : {},
    );
    final result = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        accountCatalogueRepositoryProvider.overrideWith(
          (ref) async => repository,
        ),
      ],
    );
    await result.read(authCredentialsStoreProvider.future);
    return result;
  }

  test('identity mutation waits for an admitted removal', () async {
    final repository = _Repository()
      ..started = Completer()
      ..release = Completer();
    final scope = await container(repository);
    final removal = scope
        .read(accountCatalogueActionsProvider)
        .remove(_catalogue, sessionEpoch: 0);
    final rejected = expectLater(removal, throwsStateError);
    await repository.started!.future;
    var changed = false;
    final transition = scope
        .read(authCredentialsStoreProvider.notifier)
        .withIdentityChange(() async => changed = true);
    await Future<void>.delayed(Duration.zero);
    expect(changed, isFalse);
    repository.release!.complete();
    await rejected;
    await transition;
    expect(changed, isTrue);
    expect(repository.removals, 1);
    scope.dispose();
  });
}
