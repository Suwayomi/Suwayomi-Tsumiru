import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/data/user_settings.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/downloads_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/library/data/library_settings_repository.dart';
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
  test('legacy server keeps the seven existing mutations', () async {
    access = AccountAccess(capability: AccountCapability.unsupported);
    await updateAll();
    expect(link.operations.length, 7);
    expect(link.operations, isNot(contains('SetAccountSettings')));
    expect(link.patches, isEmpty);
  });
  test('unknown capability sends no settings mutation', () async {
    access = AccountAccess(capability: AccountCapability.unknown);
    await expectLater(updateAll(), throwsStateError);
    expect(link.operations, isEmpty);
  });
  test(
    'reader cannot change shared interval, location or archive format',
    () async {
      final library = LibrarySettingsRepository(client, routing: routing);
      final downloads = DownloadsSettingsRepository(client, routing: routing);
      await expectLater(
        library.updateGlobalUpdateInterval(1),
        throwsA(isA<AccountPermissionDenied>()),
      );
      await expectLater(
        downloads.updateDownloadsLocation('/new'),
        throwsA(isA<AccountPermissionDenied>()),
      );
      await expectLater(
        downloads.updateDownloadAsCbz(true),
        throwsA(isA<AccountPermissionDenied>()),
      );
      expect(link.operations, isEmpty);
    },
  );
  test('explicit MANAGE_SETTINGS grant permits shared changes', () async {
    access = AccountAccess(
      capability: AccountCapability.supported,
      user: Fragment$AccountDto(
        id: 2,
        username: 'manager',
        permissions: [Enum$UserPermission.MANAGE_SETTINGS],
        roles: [Enum$UserRole.USER],
      ),
    );
    await LibrarySettingsRepository(
      client,
      routing: routing,
    ).updateGlobalUpdateInterval(1);
    await DownloadsSettingsRepository(
      client,
      routing: routing,
    ).updateDownloadsLocation('/new');
    expect(link.operations, [
      'UpdateGlobalUpdateInterval',
      'UpdateDownloadsLocation',
    ]);
  });
  test('legacy personal reads do not query account-only fields', () async {
    access = AccountAccess(capability: AccountCapability.unsupported);
    final container = ProviderContainer(
      overrides: [
        accountAccessProvider.overrideWith((ref) async => access),
        accountRepositoryProvider.overrideWithValue(AccountRepository(client)),
        settingsProvider.overrideWith(FixedSettings.new),
      ],
    );
    addTearDown(container.dispose);
    expect(
      (await container.read(personalSettingsProvider.future))!.excludeCompleted,
      isFalse,
    );
    expect(link.operations, isEmpty);
  });
  test('personal provider overlays user values on global settings', () async {
    final container = ProviderContainer(
      overrides: [
        accountAccessProvider.overrideWith((ref) async => access),
        accountRepositoryProvider.overrideWithValue(AccountRepository(client)),
        settingsProvider.overrideWith(FixedSettings.new),
      ],
    );
    addTearDown(container.dispose);
    final settings = await container.read(personalSettingsProvider.future);
    expect(settings!.excludeCompleted, isTrue);
    expect(settings.globalUpdateInterval, 12);
    expect(link.operations, ['AccountSettings']);
  });

  group('personalSettingsState', () {
    final supported = AccountAccess(capability: AccountCapability.supported);
    final unknown = AccountAccess(capability: AccountCapability.unknown);
    final checked = AsyncValue.data(supported);
    const checking = AsyncLoading<AccountAccess>();
    final loaded = AsyncValue<Fragment$SettingsDto?>.data(serverSettings());

    PersonalSettingsState state(
      AccountAccess access,
      AsyncValue<AccountAccess> accessCheck,
      AsyncValue<Fragment$SettingsDto?> personal,
    ) => personalSettingsState(
      access: access,
      accessCheck: accessCheck,
      personal: personal,
    );

    test('an account check in flight is loading, not unavailable', () {
      expect(
        state(unknown, checking, const AsyncLoading()),
        PersonalSettingsState.loading,
      );
    });

    test('a first load in flight is loading, not unavailable', () {
      expect(
        state(supported, checked, const AsyncLoading()),
        PersonalSettingsState.loading,
      );
    });

    test('a reload keeps the settings it already has editable', () async {
      // Riverpod flags a refresh as loading while keeping the previous value;
      // counting that as a failure flashed the "could not be verified" message.
      var pending = Future<Fragment$SettingsDto?>.value(serverSettings());
      final personal = FutureProvider<Fragment$SettingsDto?>((ref) => pending);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(personal, (_, _) {});
      await container.read(personal.future);
      pending = Completer<Fragment$SettingsDto?>().future;
      container.invalidate(personal);
      final reloading = container.read(personal);
      expect(reloading.isLoading, isTrue);
      expect(reloading.value, isNotNull);
      expect(state(supported, checked, reloading), PersonalSettingsState.ready);
    });

    test('loaded settings are ready', () {
      expect(state(supported, checked, loaded), PersonalSettingsState.ready);
    });

    test('a settled unknown account or a failed load is unavailable', () {
      expect(
        state(unknown, AsyncValue.data(unknown), loaded),
        PersonalSettingsState.unavailable,
      );
      expect(
        state(
          supported,
          checked,
          AsyncValue.error(StateError('offline'), StackTrace.empty),
        ),
        PersonalSettingsState.unavailable,
      );
      expect(
        state(supported, checked, const AsyncValue.data(null)),
        PersonalSettingsState.unavailable,
      );
    });
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
