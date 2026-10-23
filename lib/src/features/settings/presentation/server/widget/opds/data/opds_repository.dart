import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../global_providers/global_providers.dart';
import '../../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../../../account/data/account_providers.dart';
import '../../../../../../account/domain/account_access.dart';
import '../../../../../data/user_settings.dart';
import '../graphql/__generated__/opds.graphql.dart';

/// OPDS feed settings are per-user (`UserSettingsType`), read and written through [UserSettingsRouting].
typedef OpdsSettings = ({
  bool useBinaryFileSizes,
  int itemsPerPage,
  bool enablePageReadProgress,
  bool markAsReadOnDownload,
  bool showOnlyUnreadChapters,
  bool showOnlyDownloadedChapters,
  bool skipChapterMetadataFeed,
  Enum$SortOrder chapterSortOrder,
  Enum$CbzMediaType cbzMimetype,
});

class OpdsSettingsRepository {
  const OpdsSettingsRepository(this.client, {required this.routing});

  final GraphQLClient client;
  final UserSettingsRouting routing;

  /// Null when the server predates OPDS: the query itself is rejected.
  Future<Fragment$OpdsSettingsDto?> legacySettings() async {
    try {
      return await client
          .query$OpdsLegacySettings(
            Options$Query$OpdsLegacySettings(fetchPolicy: FetchPolicy.noCache),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<bool> updateUseBinaryFileSizes(bool value) => _write(
    Input$PartialUserSettingsTypeInput(opdsUseBinaryFileSizes: value),
    () => _legacyWrite(
      client.mutate$UpdateOpdsUseBinaryFileSizes(
        Options$Mutation$UpdateOpdsUseBinaryFileSizes(
          variables: Variables$Mutation$UpdateOpdsUseBinaryFileSizes(
            opdsUseBinaryFileSizes: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> updateItemsPerPage(int value) => _write(
    Input$PartialUserSettingsTypeInput(opdsItemsPerPage: value),
    () => _legacyWrite(
      client.mutate$UpdateOpdsItemsPerPage(
        Options$Mutation$UpdateOpdsItemsPerPage(
          variables: Variables$Mutation$UpdateOpdsItemsPerPage(
            opdsItemsPerPage: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> updateEnablePageReadProgress(bool value) => _write(
    Input$PartialUserSettingsTypeInput(opdsEnablePageReadProgress: value),
    () => _legacyWrite(
      client.mutate$UpdateOpdsEnablePageReadProgress(
        Options$Mutation$UpdateOpdsEnablePageReadProgress(
          variables: Variables$Mutation$UpdateOpdsEnablePageReadProgress(
            opdsEnablePageReadProgress: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> updateMarkAsReadOnDownload(bool value) => _write(
    Input$PartialUserSettingsTypeInput(opdsMarkAsReadOnDownload: value),
    () => _legacyWrite(
      client.mutate$UpdateOpdsMarkAsReadOnDownload(
        Options$Mutation$UpdateOpdsMarkAsReadOnDownload(
          variables: Variables$Mutation$UpdateOpdsMarkAsReadOnDownload(
            opdsMarkAsReadOnDownload: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> updateShowOnlyUnreadChapters(bool value) => _write(
    Input$PartialUserSettingsTypeInput(opdsShowOnlyUnreadChapters: value),
    () => _legacyWrite(
      client.mutate$UpdateOpdsShowOnlyUnreadChapters(
        Options$Mutation$UpdateOpdsShowOnlyUnreadChapters(
          variables: Variables$Mutation$UpdateOpdsShowOnlyUnreadChapters(
            opdsShowOnlyUnreadChapters: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> updateShowOnlyDownloadedChapters(bool value) => _write(
    Input$PartialUserSettingsTypeInput(opdsShowOnlyDownloadedChapters: value),
    () => _legacyWrite(
      client.mutate$UpdateOpdsShowOnlyDownloadedChapters(
        Options$Mutation$UpdateOpdsShowOnlyDownloadedChapters(
          variables: Variables$Mutation$UpdateOpdsShowOnlyDownloadedChapters(
            opdsShowOnlyDownloadedChapters: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> updateSkipChapterMetadataFeed(bool value) => _write(
    Input$PartialUserSettingsTypeInput(opdsSkipChapterMetadataFeed: value),
    () => _legacyWrite(
      client.mutate$UpdateOpdsSkipChapterMetadataFeed(
        Options$Mutation$UpdateOpdsSkipChapterMetadataFeed(
          variables: Variables$Mutation$UpdateOpdsSkipChapterMetadataFeed(
            opdsSkipChapterMetadataFeed: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> updateChapterSortOrder(Enum$SortOrder value) => _write(
    Input$PartialUserSettingsTypeInput(opdsChapterSortOrder: value),
    () => _legacyWrite(
      client.mutate$UpdateOpdsChapterSortOrder(
        Options$Mutation$UpdateOpdsChapterSortOrder(
          variables: Variables$Mutation$UpdateOpdsChapterSortOrder(
            opdsChapterSortOrder: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> updateCbzMimetype(Enum$CbzMediaType value) => _write(
    Input$PartialUserSettingsTypeInput(opdsCbzMimetype: value),
    () => _legacyWrite(
      client.mutate$UpdateOpdsCbzMimetype(
        Options$Mutation$UpdateOpdsCbzMimetype(
          variables: Variables$Mutation$UpdateOpdsCbzMimetype(
            opdsCbzMimetype: value,
          ),
        ),
      ),
    ),
  );

  /// The section re-reads [opdsSettingsProvider] from its own ref after an
  /// awaited write (same as the downloads re-upload row): invalidating
  /// from this repository's ref would throw a circular-dependency error on
  /// the legacy path, where [opdsSettingsProvider] watches this provider.
  Future<bool> _write(
    Input$PartialUserSettingsTypeInput patch,
    Future<void> Function() legacy,
  ) async {
    await routing.update(
      patch,
      () => routing.global(() async {
        await legacy();
        return null;
      }),
    );
    return true;
  }

  Future<void> _legacyWrite<T>(Future<QueryResult<T>> request) async {
    await request.getData((data) => data);
  }
}

final Provider<OpdsSettingsRepository> opdsSettingsRepositoryProvider =
    Provider<OpdsSettingsRepository>(
  (ref) => OpdsSettingsRepository(
    ref.watch(graphQlClientProvider),
    routing: ref.watch(userSettingsRoutingProvider),
  ),
);

final FutureProvider<OpdsSettings?> opdsSettingsProvider =
    FutureProvider.autoDispose<OpdsSettings?>((ref) async {
  switch (ref.watch(settledAccountAccessProvider).capability) {
    case AccountCapability.unknown:
      throw StateError('Account settings unavailable');
    case AccountCapability.supported:
      final user = await ref.watch(userSettingsProvider.future);
      if (user == null) throw StateError('Missing account settings');
      return (
        useBinaryFileSizes: user.opdsUseBinaryFileSizes,
        itemsPerPage: user.opdsItemsPerPage,
        enablePageReadProgress: user.opdsEnablePageReadProgress,
        markAsReadOnDownload: user.opdsMarkAsReadOnDownload,
        showOnlyUnreadChapters: user.opdsShowOnlyUnreadChapters,
        showOnlyDownloadedChapters: user.opdsShowOnlyDownloadedChapters,
        skipChapterMetadataFeed: user.opdsSkipChapterMetadataFeed,
        chapterSortOrder: user.opdsChapterSortOrder,
        cbzMimetype: user.opdsCbzMimetype,
      );
    case AccountCapability.unsupported:
      final settings = await ref
          .watch(opdsSettingsRepositoryProvider)
          .legacySettings();
      if (settings == null) return null;
      return (
        useBinaryFileSizes: settings.opdsUseBinaryFileSizes,
        itemsPerPage: settings.opdsItemsPerPage,
        enablePageReadProgress: settings.opdsEnablePageReadProgress,
        markAsReadOnDownload: settings.opdsMarkAsReadOnDownload,
        showOnlyUnreadChapters: settings.opdsShowOnlyUnreadChapters,
        showOnlyDownloadedChapters: settings.opdsShowOnlyDownloadedChapters,
        skipChapterMetadataFeed: settings.opdsSkipChapterMetadataFeed,
        chapterSortOrder: settings.opdsChapterSortOrder,
        cbzMimetype: settings.opdsCbzMimetype,
      );
  }
});
