import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../global_providers/global_providers.dart';
import '../../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../../../account/data/account_permission.dart';
import '../../../../../data/account_or_legacy_settings.dart';
import '../../../../../data/user_settings.dart';
import '../graphql/__generated__/images.graphql.dart';
import '../image_conversions.dart';

final Expando<Future<bool>> _clearCachedImagesSupport =
    Expando<Future<bool>>('clearCachedImagesSupport');

class ImagesRepository {
  const ImagesRepository(this.client, {required this.permissions});

  final GraphQLClient client;
  final AccountPermissionGuard permissions;

  Future<Fragment$ImagesDownloadSettingsDto?> downloadSettings() async {
    try {
      return await client
          .query$ImagesDownloadSettings(
            Options$Query$ImagesDownloadSettings(
              fetchPolicy: FetchPolicy.noCache,
            ),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<Fragment$ImagesDownloadSettingsDto?> writeDownload(
    Input$PartialSettingsTypeInput patch,
  ) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => client
        .mutate$SetImagesDownloadSettings(
          Options$Mutation$SetImagesDownloadSettings(
            variables: Variables$Mutation$SetImagesDownloadSettings(
              settings: patch,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<void> clearCachedImages() => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => client
        .mutate$ClearCachedImages(
          Options$Mutation$ClearCachedImages(
            fetchPolicy: FetchPolicy.noCache,
            variables: Variables$Mutation$ClearCachedImages(
              input: Input$ClearCachedImagesInput(
                cachedPages: true,
                cachedThumbnails: true,
              ),
            ),
          ),
        )
        .getData((data) => data),
  );

  /// Only caches definitive answers; errors throw and retry next refresh.
  Future<bool> supportsClearCachedImages() async {
    final cached = _clearCachedImagesSupport[client];
    if (cached != null) return cached;
    final result = await _introspectClearSupport();
    _clearCachedImagesSupport[client] = Future.value(result);
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
    return fields.any((f) => (f as Map)['name'] == 'clearCachedImages');
  }
}

final imagesRepositoryProvider = Provider<ImagesRepository>(
  (ref) => ImagesRepository(
    ref.watch(graphQlClientProvider),
    permissions: ref.watch(accountPermissionGuardProvider),
  ),
);

final imagesDownloadSettingsProvider =
    FutureProvider.autoDispose<Fragment$ImagesDownloadSettingsDto?>(
      (ref) => ref.watch(imagesRepositoryProvider).downloadSettings(),
    );

final clearCachedImagesSupportProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(imagesRepositoryProvider).supportsClearCachedImages(),
);

/// Serve conversions are per-user, read and written through [UserSettingsRouting].
class ServeConversionsRepository {
  const ServeConversionsRepository(this.client, {required this.routing});

  final GraphQLClient client;
  final UserSettingsRouting routing;

  /// Null when the server predates serve processing: the query is rejected.
  Future<Fragment$ImagesServeLegacySettingsDto?> legacySettings() async {
    try {
      return await client
          .query$ImagesServeLegacySettings(
            Options$Query$ImagesServeLegacySettings(
              fetchPolicy: FetchPolicy.noCache,
            ),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<void> write(
    List<Input$SettingsDownloadConversionTypeInput> conversions,
  ) async {
    await routing.update(
      Input$PartialUserSettingsTypeInput(serveConversions: conversions),
      () => routing.global(() async {
        await client
            .mutate$UpdateServeConversions(
              Options$Mutation$UpdateServeConversions(
                variables: Variables$Mutation$UpdateServeConversions(
                  serveConversions: conversions,
                ),
              ),
            )
            .getData((data) => data);
        return null;
      }),
    );
  }
}

final serveConversionsRepositoryProvider =
    Provider<ServeConversionsRepository>(
      (ref) => ServeConversionsRepository(
        ref.watch(graphQlClientProvider),
        routing: ref.watch(userSettingsRoutingProvider),
      ),
    );

final FutureProvider<List<ServerConversion>?>
serveConversionsProvider = FutureProvider.autoDispose<List<ServerConversion>?>(
  (ref) => accountOrLegacySettings(
    ref,
    fromUser: (user) {
          if (user == null) throw StateError('Missing account settings');
          return user.serveConversions
              .map(
                (c) => ServerConversion(
                  mimeType: c.mimeType,
                  target: c.target,
                  compressionLevel: c.compressionLevel,
                  callTimeout: c.callTimeout,
                  connectTimeout: c.connectTimeout,
                  headers: c.headers
                      ?.map(
                        (h) => ServerConversionHeader(
                          name: h.name,
                          value: h.value,
                        ),
                      )
                      .toList(),
                ),
              )
              .toList();
    },
    legacy: () async {
          final settings = await ref
              .watch(serveConversionsRepositoryProvider)
              .legacySettings();
          final conversions = settings?.serveConversions;
          if (conversions == null) return null;
          return conversions
              .map(
                (c) => ServerConversion(
                  mimeType: c.mimeType,
                  target: c.target,
                  compressionLevel: c.compressionLevel,
                  callTimeout: c.callTimeout,
                  connectTimeout: c.connectTimeout,
                  headers: c.headers
                      ?.map(
                        (h) => ServerConversionHeader(
                          name: h.name,
                          value: h.value,
                        ),
                      )
                      .toList(),
                ),
              )
              .toList();
    },
  ),
);
