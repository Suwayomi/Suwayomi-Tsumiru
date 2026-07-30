import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../domain/extension_store/extension_store_model.dart';
import 'graphql/__generated__/query.graphql.dart';

part 'extension_store_repository.g.dart';

class ExtensionStoreRepository {
  const ExtensionStoreRepository(this.client);
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

  Future<void> addStore(String indexUrl) => client
      .mutate$AddExtensionStore(
        Options$Mutation$AddExtensionStore(
          variables: Variables$Mutation$AddExtensionStore(indexUrl: indexUrl),
        ),
      )
      .getData((data) => null);

  Future<void> removeStore(String indexUrl) => client
      .mutate$RemoveExtensionStore(
        Options$Mutation$RemoveExtensionStore(
          variables: Variables$Mutation$RemoveExtensionStore(
            indexUrl: indexUrl,
          ),
        ),
      )
      .getData((data) => null);
}

@riverpod
ExtensionStoreRepository extensionStoreRepository(Ref ref) =>
    ExtensionStoreRepository(ref.watch(graphQlClientProvider));

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
