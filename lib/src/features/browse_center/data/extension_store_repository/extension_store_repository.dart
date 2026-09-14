import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../account/data/account_permission.dart';
import '../../domain/extension_store/extension_store_model.dart';
import 'graphql/__generated__/query.graphql.dart';

part 'extension_store_repository.g.dart';

class ExtensionStoreRepository {
  const ExtensionStoreRepository(this.client, {required this.permissions});

  final AccountPermissionGuard permissions;
  final GraphQLClient client;

  Future<({List<ExtensionStore> stores, int totalCount})?>
  getExtensionStores() => client
      .query$ExtensionStoreList(
        Options$Query$ExtensionStoreList(fetchPolicy: FetchPolicy.networkOnly),
      )
      .getData(
        (data) => (
          stores: data.extensionStores.nodes.toList(),
          totalCount: data.extensionStores.totalCount,
        ),
      );

  Future<void> addStore(String indexUrl) => permissions.run(
    Enum$UserPermission.MANAGE_EXTENSION_STORES,
    () => client
        .mutate$AddExtensionStore(
          Options$Mutation$AddExtensionStore(
            variables: Variables$Mutation$AddExtensionStore(indexUrl: indexUrl),
          ),
        )
        .getData((data) {}),
  );

  Future<void> removeStore(String indexUrl) => permissions.run(
    Enum$UserPermission.MANAGE_EXTENSION_STORES,
    () => client
        .mutate$RemoveExtensionStore(
          Options$Mutation$RemoveExtensionStore(
            variables: Variables$Mutation$RemoveExtensionStore(
              indexUrl: indexUrl,
            ),
          ),
        )
        .getData((data) {}),
  );
}

@riverpod
ExtensionStoreRepository extensionStoreRepository(Ref ref) =>
    ExtensionStoreRepository(
      ref.watch(graphQlClientProvider),
      permissions: ref.watch(accountPermissionGuardProvider),
    );

@riverpod
Future<({List<ExtensionStore> stores, int totalCount})?> extensionStoreList(
  Ref ref,
) {
  final result = ref
      .watch(extensionStoreRepositoryProvider)
      .getExtensionStores();
  ref.keepAlive();
  return result;
}
