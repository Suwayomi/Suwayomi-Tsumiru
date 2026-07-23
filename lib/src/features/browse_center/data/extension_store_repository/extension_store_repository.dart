import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../domain/extension_store/extension_store_model.dart';
import 'graphql/__generated__/query.graphql.dart';

part 'extension_store_repository.g.dart';

/// Per-client cache of the extension-store capability, keyed by GraphQLClient
/// so a server switch re-probes (same pattern as the tracker capability cache).
final Expando<Future<bool>> _storeSupportCache = Expando(
  'extensionStoreSupport',
);

/// true = store-capable, false = pre-store server (both definitive),
/// null = transient failure (network blip) — must not be memoized, or one bad
/// moment at startup pins the session to the legacy UI.
bool? classifyStoreProbe(QueryResult result) {
  if (!result.hasException) {
    return result.data?['extensionStores'] != null ? true : null;
  }
  // The server answered with GraphQL errors => it parsed the query and
  // rejected it (old schema). Link/transport failures mean it never answered.
  return result.exception!.graphqlErrors.isNotEmpty ? false : null;
}

class ExtensionStoreRepository {
  const ExtensionStoreRepository(this.client);
  final GraphQLClient client;

  Future<bool> supportsExtensionStores() {
    final cached = _storeSupportCache[client];
    if (cached != null) return cached;
    final probe = _probe().then((verdict) {
      if (verdict == null) {
        _storeSupportCache[client] = null; // allow re-probe next call
        return false;
      }
      return verdict;
    });
    _storeSupportCache[client] = probe;
    return probe;
  }

  Future<bool?> _probe() async {
    try {
      final result = await client.query(
        QueryOptions(
          document: gql('query { extensionStores { totalCount } }'),
          // networkOnly: the Hive-persisted cache would answer with the
          // pre-upgrade schema forever after a server upgrade.
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      return classifyStoreProbe(result);
    } catch (_) {
      return null;
    }
  }

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
Future<bool> extensionStoreSupport(Ref ref) {
  final result = ref
      .watch(extensionStoreRepositoryProvider)
      .supportsExtensionStores();
  ref.keepAlive();
  return result;
}

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
