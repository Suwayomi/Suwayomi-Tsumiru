import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/data/user_settings.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/downloads_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/library/data/library_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/opds/data/opds_repository.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

class SettingsLink extends Link {
  final operations = <String>[];
  final patches = <Map<String, dynamic>>[];
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    operations.add(name);
    final user = accountSettings().toJson();
    if (name == 'SetAccountSettings') {
      final patch = Map<String, dynamic>.from(
        (request.variables['input'] as Map)['userSettings'] as Map,
      );
      patches.add(patch);
      user.addAll(patch);
      yield Response(
        response: {},
        data: {
          '__typename': 'Mutation',
          'setUserSettings': {
            '__typename': 'SetUserSettingsPayload',
            'userSettings': user,
          },
        },
      );
    } else if (name == 'AccountSettings') {
      user['excludeCompleted'] = true;
      yield Response(
        response: {},
        data: {'__typename': 'Query', 'userSettings': user},
      );
    } else {
      yield Response(
        response: {},
        data: {
          '__typename': 'Mutation',
          'setSettings': {
            '__typename': 'SetSettingsPayload',
            'settings': serverSettings().toJson(),
          },
        },
      );
    }
  }
}

class FixedSettings extends Settings {
  @override
  Future<Fragment$SettingsDto?> build() async => serverSettings();
}

void main() {
  late SettingsLink link;
  late GraphQLClient client;
  late AccountAccess access;
  late UserSettingsRouting routing;
  setUp(() {
    link = SettingsLink();
    client = GraphQLClient(link: link, cache: GraphQLCache());
    access = AccountAccess(
      capability: AccountCapability.supported,
      user: Fragment$AccountDto(
        id: 2,
        username: 'reader',
        permissions: [],
        roles: [Enum$UserRole.USER],
      ),
    );
    routing = UserSettingsRouting(
      account: AccountRepository(client),
      access: () => access,
      settings: () async => serverSettings(),
      updated: () {},
    );
  });
  Future<void> updateAll() async {
    final library = LibrarySettingsRepository(client, routing: routing);
    final downloads = DownloadsSettingsRepository(client, routing: routing);
    expect((await library.updateMangaMetaData(true))!.globalUpdateInterval, 12);
    await library.toggleExcludeCompleted(true);
    await library.toggleExcludeNotStarted(true);
    await library.toggleExcludeUnreadChapters(true);
    await downloads.toggleAutoDownloadNewChapters(true);
    await downloads.updateAutoDownloadNewChaptersLimit(7);
    await downloads.toggleExcludeEntryWithUnreadChapters(true);
  }

  test('reader writes all seven fields only through userSettings', () async {
    await updateAll();
    expect(link.operations, List.filled(7, 'SetAccountSettings'));
    expect(link.patches, [
      {'updateMangas': true},
      {'excludeCompleted': true},
      {'excludeNotStarted': true},
      {'excludeUnreadChapters': true},
      {'autoDownloadNewChapters': true},
      {'autoDownloadNewChaptersLimit': 7},
      {'excludeEntryWithUnreadChapters': true},
    ]);
  });

  test('reader writes ignore-reuploads only through userSettings', () async {
    final downloads = DownloadsSettingsRepository(client, routing: routing);
    await downloads.toggleAutoDownloadIgnoreReUploads(true);
    expect(link.operations, ['SetAccountSettings']);
    expect(link.patches, [
      {'autoDownloadIgnoreReUploads': true},
    ]);
  });

  test('reader writes OPDS settings only through userSettings', () async {
    final opds = OpdsSettingsRepository(client, routing: routing);
    await opds.updateShowOnlyUnreadChapters(true);
    expect(link.operations, ['SetAccountSettings']);
    expect(link.patches, [
      {'opdsShowOnlyUnreadChapters': true},
    ]);
  });
}

Fragment$SettingsDto serverSettings() => Fragment$SettingsDto(
  backupInterval: 0,
  backupPath: '',
  backupTTL: 0,
  backupTime: '',
  ip: '',
  port: 0,
  socksProxyEnabled: false,
  socksProxyHost: '',
  socksProxyPassword: '',
  socksProxyPort: '',
  socksProxyUsername: '',
  socksProxyVersion: 0,
  flareSolverrEnabled: false,
  flareSolverrSessionName: '',
  flareSolverrSessionTtl: 0,
  flareSolverrTimeout: 0,
  flareSolverrUrl: '',
  debugLogsEnabled: false,
  systemTrayEnabled: false,
  extensionRepos: const [],
  maxSourcesInParallel: 0,
  localSourcePath: '',
  globalUpdateInterval: 12,
  updateMangas: false,
  excludeCompleted: false,
  excludeNotStarted: false,
  excludeUnreadChapters: false,
  downloadAsCbz: false,
  downloadsPath: '',
  autoDownloadNewChapters: false,
  autoDownloadNewChaptersLimit: 0,
  excludeEntryWithUnreadChapters: false,
);

Fragment$AccountSettingsDto accountSettings() => Fragment$AccountSettingsDto(
  autoDownloadIgnoreReUploads: false,
  autoDownloadNewChapters: false,
  autoDownloadNewChaptersLimit: 0,
  excludeCompleted: false,
  excludeEntryWithUnreadChapters: false,
  excludeNotStarted: false,
  excludeUnreadChapters: false,
  updateMangas: false,
  koreaderSyncChecksumMethod: Enum$KoreaderSyncChecksumMethod.values.first,
  koreaderSyncPercentageTolerance: 0,
  koreaderSyncStrategyBackward: Enum$KoreaderSyncConflictStrategy.values.first,
  koreaderSyncStrategyForward: Enum$KoreaderSyncConflictStrategy.values.first,
  opdsCbzMimetype: Enum$CbzMediaType.values.first,
  opdsChapterSortOrder: Enum$SortOrder.values.first,
  opdsEnablePageReadProgress: false,
  opdsItemsPerPage: 0,
  opdsMarkAsReadOnDownload: false,
  opdsShowOnlyDownloadedChapters: false,
  opdsShowOnlyUnreadChapters: false,
  opdsSkipChapterMetadataFeed: false,
  opdsUseBinaryFileSizes: false,
  serveConversions: const [],
  syncDataCategories: false,
  syncDataChapters: false,
  syncDataHistory: false,
  syncDataManga: false,
  syncDataTracking: false,
  syncInterval: '',
  syncYomiApiKey: '',
  syncYomiEnabled: false,
  syncYomiHost: '',
);
