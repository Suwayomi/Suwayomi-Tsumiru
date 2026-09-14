import 'package:shared_preferences/shared_preferences.dart';

import 'account_catalogue.dart';

Future<AccountCatalogueRepository> createAccountCatalogueRepository(
  SharedPreferences preferences,
) async => _NoCatalogues();

class _NoCatalogues implements AccountCatalogueRepository {
  @override
  Future<List<AccountCatalogue>> list({String? activePath}) async => [];

  @override
  Future<void> remove(
    AccountCatalogue catalogue, {
    required bool Function() canRemove,
  }) async => throw UnsupportedError('Offline storage is unavailable');
}
