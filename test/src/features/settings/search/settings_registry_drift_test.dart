// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Settings drift guard: every registry entry for a page must exist as a
// SettingsHighlightTarget on that page, and every target on the page must
// have a registry entry. Screens are pumped with every condition satisfied
// (keyboard runtime is inherent to the test VM; auto-refresh defaults on;
// theme dark + custom; recommendations on; full permissions; Reader:
// force-horizontal off, fullscreen on, flash on, split on, rotate on,
// volume keys on, Android override; Server hub pages: reachable settings
// with SOCKS and FlareSolverr on, web UI flavour set, authenticated;
// Connection: LAN address set; Sync: SyncYomi configured and KOReader
// supported; Tracking: tracker list stubbed), so a new conditional tile
// without an entry — or an entry whose tile was removed — fails here, not
// silently in search.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/app_theme.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_store_repository/extension_store_repository.dart';
import 'package:tsumiru/src/features/library/data/default_category.dart';
import 'package:tsumiru/src/features/library/domain/category/category_model.dart';
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/notifications/controller/notification_settings_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/settings/controller/server_controller.dart';
import 'package:tsumiru/src/features/settings/data/user_settings.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/domain/settings/settings.dart';
import 'package:tsumiru/src/features/settings/presentation/advanced/advanced_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/appearance/appearance_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/appearance/widgets/app_theme_selector/app_theme_providers.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/backup_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/data/backup_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/widgets/backup_flags/backup_flags.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/widgets/backup_flags/backup_flags_dialog.dart';
import 'package:tsumiru/src/features/settings/presentation/browse/browse_settings_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/connection/connection_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/downloads_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/downloads_settings_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/general/general_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/domain/koreader_sync_domain.dart';
import 'package:tsumiru/src/features/settings/presentation/library/data/library_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/library/library_settings_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/notifications/notifications_settings_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/reader_settings_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_force_horizontal_seekbar_tile/reader_force_horizontal_seekbar_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import 'package:tsumiru/src/features/settings/presentation/reader/widgets/reader_volume_tap_tile/reader_volume_tap_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/graphql/__generated__/web_interface.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/server_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/web_interface_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/server_database_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/server/server_images_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/server/server_logs_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/server/server_network_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/server/server_opds_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/server/server_web_interface_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/database/data/database_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/database/graphql/__generated__/database.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/data/images_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/graphql/__generated__/images.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/image_conversions.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/misc_settings/data/misc_logs_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/misc_settings/graphql/__generated__/misc_logs.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/opds/data/opds_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/webview/data/webview_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/webview/graphql/__generated__/webview.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/sync/sync_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_provider.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/data/syncyomi_settings_repository.dart';
import 'package:tsumiru/src/features/settings/search/settings_search_registry.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/features/tracking/presentation/settings/tracking_settings_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';
import 'package:tsumiru/src/utils/webui_meta/webui_settings.dart';

class _FixedWebUiSettings extends WebUiSettings {
  @override
  Future<Map<String, String>> build() async => {};
}

class _FixedSettings extends Settings {
  @override
  Future<SettingsDto?> build() async => _serverSettings();
}

Fragment$AutoBackupFlagsDto _autoBackupFlags() => Fragment$AutoBackupFlagsDto(
  autoBackupIncludeManga: true,
  autoBackupIncludeCategories: true,
  autoBackupIncludeChapters: true,
  autoBackupIncludeTracking: true,
  autoBackupIncludeHistory: true,
  autoBackupIncludeClientData: true,
  autoBackupIncludeServerSettings: true,
);

OpdsSettings _opdsSettings() => (
  useBinaryFileSizes: true,
  itemsPerPage: 50,
  enablePageReadProgress: true,
  markAsReadOnDownload: true,
  showOnlyUnreadChapters: false,
  showOnlyDownloadedChapters: false,
  skipChapterMetadataFeed: false,
  chapterSortOrder: Enum$SortOrder.ASC,
  cbzMimetype: Enum$CbzMediaType.MODERN,
);

/// Reachable server with SOCKS and FlareSolverr switched on, so every
/// conditional Server row renders.
SettingsDto _serverSettingsOn() => Fragment$SettingsDto(
  backupInterval: 0,
  backupPath: '',
  backupTTL: 0,
  backupTime: '',
  ip: '0.0.0.0',
  port: 4567,
  socksProxyEnabled: true,
  socksProxyHost: 'localhost',
  socksProxyPassword: '',
  socksProxyPort: '1080',
  socksProxyUsername: '',
  socksProxyVersion: 5,
  flareSolverrEnabled: true,
  flareSolverrSessionName: 'default',
  flareSolverrSessionTtl: 15,
  flareSolverrTimeout: 60,
  flareSolverrUrl: 'http://localhost:8191',
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

class _SocksFlareOnSettings extends Settings {
  @override
  Future<SettingsDto?> build() async => _serverSettingsOn();
}

/// Pins the endpoint resolver so pumping ConnectionScreen never probes the
/// LAN address over the real network.
class _FixedEndpoint extends ServerEndpointResolver {
  @override
  String? build() => DBKeys.serverUrl.initial;
}

class _EmptyCategories extends CategoryController {
  @override
  Future<List<CategoryDto>?> build() async => [];
}

class _FixedDeleteChapters extends DeleteChaptersSettingsController {
  @override
  Future<DeleteChaptersSettings> build() async =>
      const DeleteChaptersSettings();
}

class _CustomTheme extends AppThemeKey {
  @override
  AppTheme? build() => AppTheme.custom;
}

SettingsDto _serverSettings() => Fragment$SettingsDto(
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

Future<ProviderContainer> _container({List<dynamic> extra = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      webUiSettingsProvider.overrideWith(_FixedWebUiSettings.new),
      backupUserSettingsProvider.overrideWith((ref) async => true),
      ...extra,
    ],
  );
  return container;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen,
) async {
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectIdsMatchRegistry(
  WidgetTester tester,
  List<SettingsSearchEntry> registered,
) {
  expect(tester.takeException(), isNull);
  // skipOffstage: false — trailing rows are built inside the cache extent
  // but sit below the fold; they still need registry entries.
  final onScreen = tester
      .widgetList<SettingsHighlightTarget>(
        find.byType(SettingsHighlightTarget, skipOffstage: false),
      )
      .map((w) => w.id)
      .toList();
  final ids = registered.map((e) => e.id).toList();
  expect(
    onScreen.toSet(),
    ids.toSet(),
    reason: 'every entry has a target and every target has an entry',
  );
  expect(onScreen, hasLength(ids.length), reason: 'no duplicate targets');
}

void main() {
  group('settings registry drift guard', () {
    testWidgets('every screen matches its registry entries', (tester) async {
      // Long pages build their rows lazily; a tall surface mounts them all.
      tester.view.physicalSize = const Size(800, 10000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(() {
        debugAndroidOverride = null;
      });

      Future<void> pumpAndCheck(
        ProviderContainer container,
        Widget screen,
        List<SettingsSearchEntry> registered,
      ) async {
        await _pumpScreen(tester, container, screen);
        _expectIdsMatchRegistry(tester, registered);
        await tester.pumpWidget(const SizedBox.shrink());
      }

      await pumpAndCheck(
        await _container(),
        const GeneralScreen(),
        generalSettingsSearchEntries,
      );

      await pumpAndCheck(
        await _container(
          extra: [appThemeKeyProvider.overrideWith(_CustomTheme.new)],
        ),
        const AppearanceScreen(),
        appearanceSettingsSearchEntries,
      );

      final dummyLink = HttpLink('http://localhost/');
      final dummyClient = GraphQLClient(link: dummyLink, cache: GraphQLCache());
      await pumpAndCheck(
        await _container(
          extra: [
            settingsProvider.overrideWith(_FixedSettings.new),
            personalSettingsProvider.overrideWith(
              (ref) async => _serverSettings(),
            ),
            personalSettingsStateProvider.overrideWithValue(
              PersonalSettingsState.ready,
            ),
            settledAccountAccessProvider.overrideWithValue(
              AccountAccess(capability: AccountCapability.unsupported),
            ),
            categoryControllerProvider.overrideWith(_EmptyCategories.new),
            settledDefaultCategoryIdProvider.overrideWithValue(0),
            librarySettingsRepositoryProvider.overrideWithValue(
              LibrarySettingsRepository(
                dummyClient,
                routing: UserSettingsRouting(
                  account: AccountRepository(dummyClient),
                  access: () =>
                      AccountAccess(capability: AccountCapability.unsupported),
                  settings: () async => _serverSettings(),
                  updated: () {},
                ),
              ),
            ),
          ],
        ),
        const LibrarySettingsScreen(),
        librarySettingsSearchEntries,
      );

      // Android-only rows only render with the override.
      debugAndroidOverride = true;
      final readerContainer = await _container();
      // Every gate satisfied: force-horizontal off, fullscreen on, flash on,
      // split on, rotate on, volume keys on. Keyboard runtime is inherent to
      // the Linux test VM, so the mouse-speed row renders.
      readerContainer
          .read(forceHorizontalSeekbarProvider.notifier)
          .update(false);
      readerContainer.read(readerFullscreenProvider.notifier).update(true);
      readerContainer.read(flashOnPageChangeProvider.notifier).update(true);
      readerContainer.read(dualPageSplitPagedProvider.notifier).update(true);
      readerContainer.read(rotateWidePagesProvider.notifier).update(true);
      readerContainer.read(volumeTapProvider.notifier).update(true);
      await pumpAndCheck(
        readerContainer,
        const ReaderSettingsScreen(),
        readerSettingsSearchEntries,
      );
      debugAndroidOverride = null;

      await pumpAndCheck(
        await _container(
          extra: [
            settingsProvider.overrideWith(_FixedSettings.new),
            settledAccountAccessProvider.overrideWithValue(
              AccountAccess(capability: AccountCapability.unsupported),
            ),
            // The live store list retries its fetch (a pending timer the
            // test binding rejects); the count only feeds the subtitle.
            extensionStoreListProvider.overrideWith((ref) async => null),
          ],
        ),
        const BrowseSettingsScreen(),
        browseSettingsSearchEntries,
      );

      final notificationsContainer = await _container();
      // Every gate satisfied: new-chapter notifications on, so the five
      // nested rows render.
      notificationsContainer
          .read(notificationsNewChaptersEnabledProvider.notifier)
          .update(true);
      await pumpAndCheck(
        notificationsContainer,
        const NotificationsSettingsScreen(),
        notificationsSettingsSearchEntries,
      );

      await pumpAndCheck(
        await _container(
          extra: [
            settingsProvider.overrideWith(_FixedSettings.new),
            settledAccountAccessProvider.overrideWithValue(
              AccountAccess(capability: AccountCapability.unsupported),
            ),
            autoBackupFlagsProvider.overrideWith(
              (ref) async => _autoBackupFlags(),
            ),
          ],
        ),
        const BackupScreen(),
        backupSettingsSearchEntries
            .where((entry) => entry.id != 'includeUserSettings')
            .toList(),
      );

      await pumpAndCheck(
        await _container(),
        const BackupFlagsDialog(title: 'Backup data', initial: BackupFlags()),
        backupSettingsSearchEntries
            .where((entry) => entry.id == 'includeUserSettings')
            .toList(),
      );

      // The background-catchup rows only render on native Android
      // (isAndroidNative), so they can have registry entries without mounted
      // targets here. Everything else must match in both directions.
      final androidOnlyDownloadsIds = {
        'backgroundCatchup',
        'backgroundCheckInterval',
        'backgroundFetchFiles',
      };

      List<SettingsSearchEntry> testableDownloadsEntries() =>
          downloadsSettingsSearchEntries
              .where(
                (e) =>
                    e.tabIndex == 1 && !androidOnlyDownloadsIds.contains(e.id),
              )
              .toList();

      Future<ProviderContainer> downloadsContainer() async {
        final container = await _container(
          extra: [
            settingsProvider.overrideWith(_FixedSettings.new),
            personalSettingsProvider.overrideWith(
              (ref) async => _serverSettings(),
            ),
            personalSettingsStateProvider.overrideWithValue(
              PersonalSettingsState.ready,
            ),
            settledAccountAccessProvider.overrideWithValue(
              AccountAccess(capability: AccountCapability.unsupported),
            ),
            categoryControllerProvider.overrideWith(_EmptyCategories.new),
            // The live controller fetches global metas with retry (a pending
            // timer the test binding rejects); the rows only read its value.
            deleteChaptersSettingsControllerProvider.overrideWith(
              _FixedDeleteChapters.new,
            ),
            // The live ignore-reuploads read hits the network the same way,
            // so the row only renders with the gate satisfied.
            autoDownloadIgnoreReUploadsProvider.overrideWith(
              (ref) async => true,
            ),
            // Same gate for the image-processing row WebUI links from here.
            imagesDownloadSettingsProvider.overrideWith(
              (ref) async => Fragment$ImagesDownloadSettingsDto(
                downloadConversions: const [],
              ),
            ),
            offlineEnabledProvider.overrideWithValue(true),
            offlineUsageBytesProvider.overrideWith((ref) async => 0),
          ],
        );
        // Mounts the keep-window switch under the on-device delete section.
        container.read(localDeleteWhileReadingProvider.notifier).update(2);
        return container;
      }

      // TabBarView only mounts the current tab, so each tab is opened once
      // to prove its ids exist on the tab its entries open.
      await pumpAndCheck(
        await downloadsContainer(),
        const DownloadsSettingsScreen(initialTab: 0),
        downloadsSettingsSearchEntries.where((e) => e.tabIndex == 0).toList(),
      );
      await pumpAndCheck(
        await downloadsContainer(),
        const DownloadsSettingsScreen(initialTab: 1),
        testableDownloadsEntries(),
      );

      // The Server hub itself is a link list with no highlight targets, so
      // each hub page is pumped against its own entries instead.
      Future<ProviderContainer> serverHubPageContainer({
        required bool socksFlareOn,
      }) async => _container(
        extra: [
          settingsProvider.overrideWith(
            socksFlareOn ? _SocksFlareOnSettings.new : _FixedSettings.new,
          ),
          // Authenticated + MANAGE_SETTINGS, like a logged-out legacy
          // server: the web rows and Check for update all render.
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: AccountCapability.unsupported),
          ),
          webInterfaceSettingsProvider.overrideWith(
            (ref) async => Fragment$WebInterfaceSettingsDto(
              webUIFlavor: Enum$WebUIFlavor.WEBUI,
              webUIChannel: Enum$WebUIChannel.STABLE,
              webUIUpdateCheckInterval: 12,
              initialOpenInBrowserEnabled: true,
              webUIInterface: Enum$WebUIInterface.ELECTRON,
              electronPath: '',
            ),
          ),
          webInterfaceFlavorsProvider.overrideWith(
            (ref) async => const [Enum$WebUIFlavor.WEBUI, Enum$WebUIFlavor.VUI],
          ),
          installedWebInterfaceProvider.overrideWith((ref) async => null),
          // The gated rows only render with their gates satisfied, like
          // every other conditional row in this fixture.
          flareSolverrFallbackProvider.overrideWith((ref) async => true),
          opdsSettingsProvider.overrideWith((ref) async => _opdsSettings()),
          previewDatabaseSettingsProvider.overrideWith(
            (ref) async => Query$PreviewDatabaseSettings$settings(
              databaseSchema: 'suwayomi',
              hikariMaxPoolSize: 6,
            ),
          ),
          databaseSettingsProvider.overrideWith(
            (ref) async => Fragment$DatabaseSettingsDto(
              databaseType: Enum$DatabaseType.POSTGRESQL,
              databaseUrl: 'postgresql://localhost:5432/suwayomi',
              databaseUsername: 'suwayomi',
              databasePassword: 'secret',
              useHikariConnectionPool: true,
            ),
          ),
          miscLogsSettingsProvider.overrideWith(
            (ref) async => Fragment$MiscLogsSettingsDto(
              maxLogFiles: 7,
              maxLogFileSize: '1MB',
              maxLogFolderSize: '10MB',
            ),
          ),
          webViewSettingsProvider.overrideWith(
            (ref) async => Fragment$WebViewSettingsDto(kcefEnabled: true),
          ),
          clearCookiesAndCacheSupportProvider.overrideWith((ref) async => true),
          imagesDownloadSettingsProvider.overrideWith(
            (ref) async => Fragment$ImagesDownloadSettingsDto(
              downloadConversions: [
                Fragment$ImagesDownloadSettingsDto$downloadConversions(
                  mimeType: 'image/jpeg',
                  target: 'image/webp',
                  compressionLevel: 0.8,
                ),
              ],
            ),
          ),
          serveConversionsProvider.overrideWith(
            (ref) async => [
              ServerConversion(
                mimeType: 'image/png',
                target: 'https://converter.example/process',
              ),
            ],
          ),
          clearCachedImagesSupportProvider.overrideWith((ref) async => true),
        ],
      );

      await pumpAndCheck(
        await serverHubPageContainer(socksFlareOn: true),
        const ServerNetworkScreen(),
        serverNetworkSettingsSearchEntries,
      );
      await pumpAndCheck(
        await serverHubPageContainer(socksFlareOn: false),
        const ServerWebInterfaceScreen(),
        serverWebInterfaceSettingsSearchEntries,
      );
      await pumpAndCheck(
        await serverHubPageContainer(socksFlareOn: false),
        const ServerOpdsScreen(),
        serverOpdsSettingsSearchEntries,
      );
      await pumpAndCheck(
        await serverHubPageContainer(socksFlareOn: false),
        const ServerImagesScreen(),
        serverImagesSettingsSearchEntries,
      );
      await pumpAndCheck(
        await serverHubPageContainer(socksFlareOn: false),
        const ServerDatabaseScreen(),
        serverDatabaseSettingsSearchEntries,
      );
      await pumpAndCheck(
        await serverHubPageContainer(socksFlareOn: false),
        const ServerLogsScreen(),
        serverLogsSettingsSearchEntries,
      );

      SharedPreferences.setMockInitialValues({
        DBKeys.serverLanUrl.name: 'http://192.168.1.100:4567',
      });
      final connectionContainer = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          serverEndpointResolverProvider.overrideWith(_FixedEndpoint.new),
        ],
      );
      await pumpAndCheck(
        connectionContainer,
        const ConnectionScreen(),
        connectionSettingsSearchEntries,
      );

      await pumpAndCheck(
        await _container(
          extra: [
            syncYomiSettingsProvider.overrideWith(
              (ref) async => const SyncYomiSettings(
                enabled: true,
                host: 'https://sync.example',
                apiKey: 'key',
                interval: 'PT1H',
                dataManga: true,
                dataChapters: true,
                dataCategories: true,
                dataHistory: true,
                dataTracking: true,
              ),
            ),
            lastSyncStatusProvider.overrideWith((ref) async => null),
            koreaderSyncSettingsProvider.overrideWith(
              (ref) async => (
                strategyForward: Enum$KoreaderSyncConflictStrategy.PROMPT,
                strategyBackward: Enum$KoreaderSyncConflictStrategy.PROMPT,
                checksumMethod: Enum$KoreaderSyncChecksumMethod.BINARY,
                percentageTolerance: 0.05,
              ),
            ),
            koSyncStatusProvider.overrideWith(
              (ref) async => const KoSyncStatus(isLoggedIn: false),
            ),
          ],
        ),
        const SyncScreen(),
        syncSettingsSearchEntries,
      );

      await pumpAndCheck(
        await _container(),
        const AdvancedScreen(),
        advancedSettingsSearchEntries,
      );

      await pumpAndCheck(
        await _container(
          extra: [
            trackersProvider.overrideWith(
              (ref) async => <Fragment$TrackerDto>[],
            ),
          ],
        ),
        const TrackingSettingsScreen(),
        trackingSettingsSearchEntries,
      );
    });
  });
}
