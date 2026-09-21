import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../global_providers/global_providers.dart';
import '../../auth/data/auth_credentials_store.dart';
import 'account_catalogue.dart';
import 'account_catalogue_repository.dart';
import 'offline_runtime_storage.dart';

final accountCatalogueRepositoryProvider =
    FutureProvider<AccountCatalogueRepository>(
      (ref) => createAccountCatalogueRepository(
        ref.watch(sharedPreferencesProvider),
      ),
    );

final inactiveAccountCataloguesProvider =
    FutureProvider<List<AccountCatalogue>>((ref) async {
      final storage = ref.watch(offlineRuntimeStorageProvider);
      final binding = ref
          .watch(authCredentialsStoreProvider)
          .value
          ?.accountBinding;
      final repository = await ref.watch(
        accountCatalogueRepositoryProvider.future,
      );
      final catalogues = await repository.list(
        activePath: storage?.paths.baseDir,
      );
      return catalogues
          .where(
            (catalogue) =>
                catalogue.isNonAccount || catalogue.id != binding?.catalogId,
          )
          .toList();
    });

final accountCatalogueActionsProvider = Provider<AccountCatalogueActions>(
  AccountCatalogueActions.new,
);

class AccountCatalogueActions {
  AccountCatalogueActions(this.ref);
  final Ref ref;

  Future<void> remove(
    AccountCatalogue catalogue, {
    required int sessionEpoch,
  }) async {
    final auth = ref.read(authCredentialsStoreProvider.notifier);
    final current = auth.captureSession();
    final saved = await auth.commitForSession(sessionEpoch, () async {
      final repository = await ref.read(
        accountCatalogueRepositoryProvider.future,
      );
      bool canRemove() {
        if (!current()) return false;
        final binding = ref
            .read(authCredentialsStoreProvider)
            .value
            ?.accountBinding;
        final path = ref.read(offlineRuntimeStorageProvider)?.paths.baseDir;
        return (catalogue.isNonAccount || binding?.catalogId != catalogue.id) &&
            (path == null || !p.equals(path, catalogue.path));
      }

      await repository.remove(catalogue, canRemove: canRemove);
    });
    if (!saved) throw StateError('Authentication session changed');
    if (ref.mounted) ref.invalidate(inactiveAccountCataloguesProvider);
  }
}
