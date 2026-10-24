import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' show MultipartFile;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/controller/source_manga_controller.dart';
import 'package:tsumiru/src/features/library/domain/library_search_query.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/download_ahead.dart';
import 'package:tsumiru/src/features/settings/data/user_settings.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/data/backup_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/widgets/backup_flags/backup_flags.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/widgets/backup_flags/backup_flags_dialog.dart';
import 'package:tsumiru/src/features/settings/presentation/library/data/library_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/database/data/database_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/database/database_section.dart';
import 'package:tsumiru/src/features/tracking/domain/tracking_settings_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/webui_meta/webui_settings.dart';

import '../../../helpers/legacy_account_access.dart';
import '../manga_book/manga_details/chapter_test_helpers.dart';

String _name(Request request) => request.operation.document.definitions
    .whereType<OperationDefinitionNode>()
    .single
    .name!
    .value;

class _Link extends Link {
  _Link(this.reply);
  final Response Function(Request) reply;
  final requests = <Request>[];
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    requests.add(request);
    yield reply(request);
  }
}

Response _data(Map<String, dynamic> data) => Response(
  response: {},
  data: {
    '__typename':
        data.keys.any(
          (key) =>
              key.startsWith('set') ||
              key.startsWith('update') ||
              key.startsWith('create') ||
              key.startsWith('restore'),
        )
        ? 'Mutation'
        : 'Query',
    ...data,
  },
);
Response _unknown(String field) => Response(
  response: {},
  errors: [
    GraphQLError(
      message: 'Cannot query field "$field" on type "SettingsType".',
    ),
  ],
);
GraphQLClient _client(_Link link) =>
    GraphQLClient(link: link, cache: GraphQLCache());

const _database = {
  '__typename': 'SettingsType',
  'databaseType': 'POSTGRESQL',
  'databaseUrl': 'postgresql://localhost/suwayomi',
  'databaseUsername': 'suwayomi',
  'databasePassword': 'secret',
  'useHikariConnectionPool': false,
};
const _auto = {
  '__typename': 'SettingsType',
  'autoBackupIncludeManga': true,
  'autoBackupIncludeCategories': false,
  'autoBackupIncludeChapters': true,
  'autoBackupIncludeTracking': true,
  'autoBackupIncludeHistory': true,
  'autoBackupIncludeClientData': true,
  'autoBackupIncludeServerSettings': true,
};

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

class _UnusedRouting implements UserSettingsRouting {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Fragment$MangaDto _manga(
  int id, {
  required String title,
  int unreadCount = 0,
}) => Fragment$MangaDto(
  id: id,
  title: title,
  chapters: Fragment$MangaDto$chapters(totalCount: 5),
  genre: const [],
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/$id',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: unreadCount,
  ),
);

void main() {
  testWidgets(
    'stable Database keeps existing fields when preview fields are unknown',
    (tester) async {
      final link = _Link(
        (request) => _name(request) == 'PreviewDatabaseSettings'
            ? _unknown('databaseSchema')
            : _data({'settings': _database}),
      );
      final container = ProviderContainer(
        overrides: [
          graphQlClientProvider.overrideWithValue(_client(link)),
          databaseSettingsRepositoryProvider.overrideWithValue(
            DatabaseSettingsRepository(
              _client(link),
              permissions: legacyAccountPermissions,
            ),
          ),
          settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(container, const DatabaseSection()));
      await tester.pumpAndSettle();
      expect(find.text('postgresql://localhost/suwayomi'), findsOneWidget);
      expect(find.text('Schema'), findsNothing);
      expect(find.text('Maximum connections'), findsNothing);
      expect(
        await container.read(previewDatabaseSettingsProvider.future),
        isNull,
      );
      expect(
        (await container.read(
          databaseSettingsProvider.future,
        ))!.databaseUsername,
        'suwayomi',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stable backup picker and existing flags survive unsupported user settings',
    (tester) async {
      final link = _Link((request) {
        switch (_name(request)) {
          case 'BackupUserSettingsCapability':
            return _unknown('autoBackupIncludeUserSettings');
          case 'AutoBackupFlags':
            return _data({'settings': _auto});
          case 'UpdateAutoBackupFlags':
            expect(
              (request.variables['settings'] as Map).containsKey(
                'autoBackupIncludeUserSettings',
              ),
              isFalse,
            );
            return _data({
              'setSettings': {
                '__typename': 'SetSettingsPayload',
                'settings': _auto,
              },
            });
          case 'CreateBackup':
            expect(
              (request.variables['flags'] as Map).containsKey(
                'includeUserSettings',
              ),
              isFalse,
            );
            return _data({
              'createBackup': {
                '__typename': 'CreateBackupPayload',
                'clientMutationId': null,
                'url': '/backup.gz',
              },
            });
          case 'RestoreBackup':
            expect(
              (request.variables['flags'] as Map).containsKey(
                'includeUserSettings',
              ),
              isFalse,
            );
            return _data({
              'restoreBackup': {
                '__typename': 'RestoreBackupPayload',
                'clientMutationId': null,
                'id': 'restore',
                'status': {
                  '__typename': 'BackupRestoreStatus',
                  'mangaProgress': 0,
                  'totalManga': 0,
                  'state': 'IDLE',
                },
              },
            });
          default:
            throw StateError('Unexpected ${_name(request)}');
        }
      });
      final repo = BackupSettingsRepository(
        _client(link),
        permissions: legacyAccountPermissions,
      );
      final container = ProviderContainer(
        overrides: [backupSettingsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final auto = await repo.autoBackupFlags();
      expect(auto!.autoBackupIncludeCategories, isFalse);
      await tester.pumpWidget(
        _app(
          container,
          BackupFlagsDialog(
            title: 'Backup data',
            initial: BackupFlags.fromAuto(auto),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Server settings'), findsOneWidget);
      expect(find.text('User settings'), findsNothing);
      const flags = BackupFlags(includeUserSettings: false);
      expect(await repo.createBackup(flags), '/backup.gz');
      expect(
        await repo.restoreBackup(MultipartFile.fromString('backup', ''), flags),
        'restore',
      );
      expect(
        (await repo.updateAutoBackupFlags(flags))!.autoBackupIncludeManga,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview backup picker defaults user settings on and serializes changes',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          backupUserSettingsProvider.overrideWith((ref) async => false),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _app(
          container,
          const BackupFlagsDialog(title: 'Backup data', initial: BackupFlags()),
        ),
      );
      await tester.pumpAndSettle();
      final tile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'User settings'),
      );
      expect(tile.value, isTrue);
      const flags = BackupFlags(includeUserSettings: false);
      expect(
        flags
            .toPartialInput(supportsUserSettings: true)
            .toJson()['includeUserSettings'],
        isFalse,
      );
      expect(
        flags
            .toAutoInput(supportsUserSettings: true)
            .toJson()['autoBackupIncludeUserSettings'],
        isFalse,
      );
      expect(
        const BackupFlags()
            .toPartialInput(supportsUserSettings: true)
            .includeUserSettings,
        isTrue,
      );
    },
  );

  test(
    'fuzzy plain terms allow typos and accents without changing metatags',
    () {
      const fields = LibraryFilterFields(
        title: 'The Archmage Returns After 4000 Years',
        unreadCount: 1,
        trackers: {'anilist'},
      );
      expect(
        LibrarySearchQuery.parse(
          'archmage retruns tracked:anilist unread:true',
        ).matches(fields, fuzzy: true),
        isTrue,
      );
      expect(
        LibrarySearchQuery.parse('archmage retruns').matches(fields),
        isFalse,
      );
      expect(
        LibrarySearchQuery.parse(
          'archmage unread:false',
        ).matches(fields, fuzzy: true),
        isFalse,
      );
      expect(
        LibrarySearchQuery.parse(
          'archmage tracked:anilits',
        ).matches(fields, fuzzy: true),
        isFalse,
      );
      expect(fuzzyLibraryWordMatches('eclair', 'Éclair'), isTrue);
      expect(fuzzyLibraryWordMatches('unrelated', fields.title), isFalse);
      expect(
        LibrarySearchQuery.parse('-retruns').matches(fields, fuzzy: true),
        isFalse,
      );
    },
  );

  test(
    'download ahead uses strict quarter boundary and slices unread before skipping downloads and queue',
    () {
      final chapters = [
        ch(id: 6, number: 6, sourceOrder: 0),
        ch(id: 5, number: 5, sourceOrder: 1, isRead: true),
        ch(id: 4, number: 4, sourceOrder: 2),
        ch(id: 3, number: 3, sourceOrder: 3, isDownloaded: true),
        ch(id: 2, number: 2, sourceOrder: 4, isDownloaded: true),
        ch(id: 1, number: 1, sourceOrder: 5, isDownloaded: true),
      ];
      final current = chapters.last.copyWith(pageCount: 4);
      List<int> run({
        int page = 1,
        int limit = 2,
        Set<int> queued = const {},
        bool nextDownloaded = true,
      }) => chapterIdsForDownloadAhead(
        chapter: current,
        nextChapter: chapters[4].copyWith(
          user: chapters[4].user.copyWith(isDownloaded: nextDownloaded),
        ),
        chapters: [
          for (final c in chapters)
            c.id == 2
                ? c.copyWith(
                    user: c.user.copyWith(isDownloaded: nextDownloaded),
                  )
                : c,
        ],
        pageIndex: page,
        limit: limit,
        queued: queued,
      );
      expect(run(page: 0), isEmpty);
      expect(run(limit: 0), isEmpty);
      expect(run(nextDownloaded: false), isEmpty);
      expect(run(), isEmpty);
      expect(run(limit: 3), [4]);
      expect(run(limit: 3, queued: {4}), isEmpty);
      expect(run(limit: 4), [6, 4]);
    },
  );

  test(
    'tracking reads server first, preserves explicit local fallback and writes only on change',
    () async {
      for (final local in [null, false, true]) {
        SharedPreferences.setMockInitialValues({
          DBKeys.updateProgressManualMarkRead.name: ?local,
        });
        var metas = <String, String>{};
        final link = _Link((request) {
          if (_name(request) == 'GetWebUiGlobalMetas') {
            return _data({
              'metas': {
                '__typename': 'GlobalMetaNodeList',
                'nodes': [
                  for (final e in metas.entries)
                    {
                      '__typename': 'GlobalMetaType',
                      'key': e.key,
                      'value': e.value,
                    },
                ],
              },
            });
          }
          return _data({
            'setGlobalMetas': {'__typename': 'SetGlobalMetasPayload'},
          });
        });
        final container = ProviderContainer(
          overrides: [
            graphQlClientProvider.overrideWithValue(_client(link)),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
        );
        final first = container.listen(
          updateProgressAfterReadingProvider,
          (_, _) {},
        );
        final second = container.listen(
          updateProgressManualMarkReadProvider,
          (_, _) {},
        );
        await container.read(webUiSettingsProvider.future);
        expect(container.read(updateProgressAfterReadingProvider), isTrue);
        expect(
          container.read(updateProgressManualMarkReadProvider),
          local ?? true,
        );
        expect(
          link.requests.where((r) => _name(r) == 'SetWebUiGlobalMetas'),
          isEmpty,
        );
        metas = {
          'webUI_updateProgressManualMarkRead': 'true',
          'webUI_updateProgressAfterReading': 'false',
        };
        container.invalidate(webUiSettingsProvider);
        await container.read(webUiSettingsProvider.future);
        expect(container.read(updateProgressManualMarkReadProvider), isTrue);
        expect(container.read(updateProgressAfterReadingProvider), isFalse);
        await container
            .read(updateProgressManualMarkReadProvider.notifier)
            .update(false);
        final write = link.requests.last;
        expect(_name(write), 'SetWebUiGlobalMetas');
        expect((write.variables['input'] as Map)['metas'], [
          {'key': 'webUI_updateProgressManualMarkRead', 'value': 'false'},
        ]);
        first.close();
        second.close();
        container.dispose();
      }
    },
  );

  test(
    'forget categories reads WebUI setting and clears only when enabled',
    () async {
      for (final forget in [false, true]) {
        final link = _Link((request) {
          switch (_name(request)) {
            case 'GetWebUiGlobalMetas':
              return _data({
                'metas': {
                  '__typename': 'GlobalMetaNodeList',
                  'nodes': [
                    {
                      '__typename': 'GlobalMetaType',
                      'key': 'webUI_removeMangaFromCategories',
                      'value': '$forget',
                    },
                  ],
                },
              });
            case 'UpdateMangasCategories':
              expect(
                (request.variables['input'] as Map)['patch']['clearCategories'],
                isTrue,
              );
              return _data({
                'updateMangasCategories': {
                  '__typename': 'UpdateMangasCategoriesPayload',
                  'mangas': [
                    {'__typename': 'MangaType', 'id': 1},
                  ],
                },
              });
            case 'UpdateManga':
              final manga = _manga(1, title: 'Series');
              return _data({
                'updateManga': {
                  '__typename': 'UpdateMangaPayload',
                  'manga': manga
                      .copyWith(user: manga.user.copyWith(inLibrary: false))
                      .toJson(),
                },
              });
            default:
              throw StateError('Unexpected request');
          }
        });
        await MangaBookRepository(_client(link)).removeMangaFromLibrary(1);
        expect(
          link.requests
              .where((r) => _name(r) == 'UpdateMangasCategories')
              .length,
          forget ? 1 : 0,
        );
        expect(link.requests.map(_name).toList(), [
          'GetWebUiGlobalMetas',
          'UpdateManga',
          if (forget) 'UpdateMangasCategories',
        ]);
        expect(
          link.requests
              .singleWhere((request) => _name(request) == 'UpdateManga')
              .variables['input'],
          {
            'id': 1,
            'patch': {'inLibrary': false},
          },
        );
      }
    },
  );

  test('ignore filters while searching keeps metatags and category scope', () {
    final mangas = [
      _manga(1, title: 'One Piece'),
      _manga(2, title: 'One Piece'),
    ];
    List<int> run({
      required bool ignore,
      String? query = 'one unread:false',
      Set<int>? ids,
    }) => applyLibraryFilterSort(
      mangas,
      query: query,
      mangaIds: ids,
      ignoreFilters: ignore,
      mangaFilterUnread: true,
      mangaFilterDownloaded: null,
      mangaFilterCompleted: null,
      mangaFilterStarted: null,
      mangaFilterBookmarked: null,
      mangaFilterOffline: null,
      offlineMangaIds: {},
      mangaFilterLewd: null,
      mangaFilterMinRating: 0,
      filterCategories: false,
      filterCategoriesInclude: {},
      filterCategoriesExclude: {},
      filterTags: false,
      filterTagsInclude: {},
      filterTagsExclude: {},
      sortedBy: MangaSort.alphabetical,
      sortedDirection: true,
    ).map((m) => m.id).toList();
    expect(run(ignore: false), isEmpty);
    expect(run(ignore: true), [1, 2]);
    expect(run(ignore: true, ids: {2}), [2]);
    expect(run(ignore: true, query: null), isEmpty);
    expect(run(ignore: true, query: 'one unread:true'), isEmpty);
  });

  test(
    'source browse hiding keeps non-library entries and can be disabled',
    () {
      final library = _manga(1, title: 'Library');
      final outside = _manga(
        2,
        title: 'Outside',
      ).copyWith(user: library.user.copyWith(inLibrary: false));
      expect(
        visibleSourceMangas([
          library,
          outside,
        ], hideLibraryEntries: true).map((m) => m.id),
        [2],
      );
      expect(
        visibleSourceMangas([
          library,
          outside,
        ], hideLibraryEntries: false).map((m) => m.id),
        [1, 2],
      );
      expect(visibleSourceMangas([library], hideLibraryEntries: true), isEmpty);
    },
  );

  test(
    'cleanup uses WebUI non-library category filter and clears matching assignments',
    () async {
      final link = _Link((request) {
        if (_name(request) == 'NonLibraryCategorizedMangas') {
          return _data({
            'mangas': {
              '__typename': 'MangaNodeList',
              'nodes': [
                {'__typename': 'MangaType', 'id': 7},
                {'__typename': 'MangaType', 'id': 8},
              ],
            },
          });
        }
        expect(request.variables['input'], {
          'ids': [7, 8],
          'patch': {'clearCategories': true},
        });
        return _data({
          'updateMangasCategories': {
            '__typename': 'UpdateMangasCategoriesPayload',
            'mangas': [
              {'__typename': 'MangaType', 'id': 7},
              {'__typename': 'MangaType', 'id': 8},
            ],
          },
        });
      });
      await LibrarySettingsRepository(
        _client(link),
        routing: _UnusedRouting(),
      ).cleanupDatabase();
      final query = printNode(link.requests.first.operation.document);
      expect(query, contains('inLibrary: {equalTo: false}'));
      expect(query, contains('categoryId: {isNull: false}'));
      expect(link.requests.map((r) => _name(r)), [
        'NonLibraryCategorizedMangas',
        'CleanupLibraryCategories',
      ]);
    },
  );
}
