import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../global_providers/global_providers.dart';
import '../../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../../../account/data/account_permission.dart';
import '../graphql/__generated__/webview.graphql.dart';

final Expando<Future<bool>> _clearCookiesAndCacheSupport =
    Expando<Future<bool>>('clearCookiesAndCacheSupport');

class WebViewRepository {
  const WebViewRepository(this.client, {required this.permissions});

  final GraphQLClient client;
  final AccountPermissionGuard permissions;

  Future<Fragment$WebViewSettingsDto?> settings() async {
    try {
      return await client
          .query$WebViewSettings(
            Options$Query$WebViewSettings(fetchPolicy: FetchPolicy.noCache),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<Fragment$WebViewSettingsDto?> write(
    Input$PartialSettingsTypeInput patch,
  ) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => client
        .mutate$SetWebViewSettings(
          Options$Mutation$SetWebViewSettings(
            variables: Variables$Mutation$SetWebViewSettings(settings: patch),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<void> clearCookiesAndCache() => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => client
        .mutate$ClearWebViewCookiesAndCache(
          Options$Mutation$ClearWebViewCookiesAndCache(
            fetchPolicy: FetchPolicy.noCache,
          ),
        )
        .getData((data) => data),
  );

  /// Only caches definitive answers; errors throw and retry next refresh.
  Future<bool> supportsClearCookiesAndCache() async {
    final cached = _clearCookiesAndCacheSupport[client];
    if (cached != null) return cached;
    final result = await _introspectClearSupport();
    _clearCookiesAndCacheSupport[client] = Future.value(result);
    return result;
  }

  Future<bool> _introspectClearSupport() async {
    final result = await client.query(
      QueryOptions(
        document: gql('query { __type(name: "Mutation") { fields { name } } }'),
        fetchPolicy: FetchPolicy.cacheFirst,
      ),
    );
    if (result.hasException) throw result.exception!;
    final fields =
        (result.data?['__type']?['fields'] as List?)?.cast<dynamic>() ??
        const [];
    return fields.any((f) => (f as Map)['name'] == 'clearCookiesAndCache');
  }
}

final webViewRepositoryProvider = Provider<WebViewRepository>(
  (ref) => WebViewRepository(
    ref.watch(graphQlClientProvider),
    permissions: ref.watch(accountPermissionGuardProvider),
  ),
);

final webViewSettingsProvider =
    FutureProvider.autoDispose<Fragment$WebViewSettingsDto?>(
      (ref) => ref.watch(webViewRepositoryProvider).settings(),
    );

final clearCookiesAndCacheSupportProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(webViewRepositoryProvider).supportsClearCookiesAndCache(),
);
