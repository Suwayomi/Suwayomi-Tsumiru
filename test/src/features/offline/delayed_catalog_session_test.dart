import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/library/data/category_repository.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_cover_warmer.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_sync.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

import '../manga_book/manga_details/chapter_test_helpers.dart';

GraphQLClient _client() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _Session extends AuthCredentialsStore {
  int epoch = 0;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState();
}

class _Library extends CategoryRepository {
  _Library() : super(_client());
  final entered = Completer<void>();
  final response = Completer<List<MangaDto>?>();
  @override
  Future<List<MangaDto>?> getAllLibraryMangas() {
    entered.complete();
    return response.future;
  }
}

class _Details extends MangaBookRepository {
  _Details() : super(_client());
  final entered = Completer<void>();
  final manga = Completer<MangaDto?>();
  final chapters = Completer<List<ChapterDto>?>();
  int sourceFetches = 0;
  @override
  Future<MangaDto?> getManga({required int mangaId}) {
    entered.complete();
    return manga.future;
  }

  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) {
    entered.complete();
    return chapters.future;
  }

  @override
  Future<List<ChapterDto>?> getMangaAndChapterList(int mangaId) async {
    sourceFetches++;
    return [ch(id: 2, number: 2)];
  }
}

class _Sync extends Fake implements OfflineSync {
  int mangaWrites = 0;
  int chapterWrites = 0;
  int prunes = 0;
  @override
  int get syncGeneration => 0;
  @override
  Future<void> syncManga(
    MangaDto manga, {
    required int fetchedAtGen,
    bool isSettleRetry = false,
  }) async {
    mangaWrites++;
  }

  @override
  Future<Set<int>> syncChapters(List<ChapterDto> chapters) async {
    chapterWrites++;
    return {};
  }

  @override
  Future<void> pruneRemovedLibraryManga(List<MangaDto> serverLibrary) async {
    prunes++;
  }
}

class _Covers extends OfflineCoverWarmer {
  int calls = 0;
  @override
  void build() {}
  @override
  Future<void> warmLibraryCovers(List<MangaDto> mangas) async {
    calls++;
  }
}

MangaDto _manga() => MangaDto(
  id: 1,
  title: 'First account',
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 1),
  downloadCount: 0,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
  unreadCount: 1,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Session auth;
  late _Library library;
  late _Details details;
  late _Sync sync;
  late _Covers covers;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    auth = _Session();
    library = _Library();
    details = _Details();
    sync = _Sync();
    covers = _Covers();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authCredentialsStoreProvider.overrideWith(() => auth),
        categoryRepositoryProvider.overrideWithValue(library),
        mangaBookRepositoryProvider.overrideWithValue(details),
        offlineReadDatabaseProvider.overrideWithValue(null),
        offlineActiveProvider.overrideWithValue(false),
        offlineSyncProvider.overrideWithValue(sync),
        offlineCoverWarmerProvider.overrideWith(() => covers),
      ],
    );
    await container.read(authCredentialsStoreProvider.future);
  });
  tearDown(() => container.dispose());

  test('current library response still mirrors and warms covers', () async {
    container.listen(libraryMangaListProvider, (_, _) {});
    final pending = container.read(libraryMangaListProvider.future);
    await library.entered.future;
    library.response.complete([_manga()]);
    expect((await pending)!.single.id, 1);
    expect(sync.mangaWrites, 1);
    expect(sync.prunes, 1);
    expect(covers.calls, 1);
  });

  test(
    'delayed library from previous account cannot mirror prune or warm covers',
    () async {
      container.listen(libraryMangaListProvider, (_, _) {});
      final pending = container.read(libraryMangaListProvider.future);
      await library.entered.future;
      auth.epoch++;
      library.response.complete([_manga()]);
      expect(await pending, isNull);
      expect(sync.mangaWrites, 0);
      expect(sync.prunes, 0);
      expect(covers.calls, 0);
    },
  );

  test(
    'delayed manga details from previous account cannot mirror metadata',
    () async {
      container.listen(mangaWithIdProvider(mangaId: 1), (_, _) {});
      final pending = container.read(mangaWithIdProvider(mangaId: 1).future);
      await details.entered.future;
      auth.epoch++;
      details.manga.complete(_manga());
      expect(await pending, isNull);
      expect(sync.mangaWrites, 0);
    },
  );

  test(
    'delayed chapters from previous account cannot mirror or fetch source',
    () async {
      final pending = container.read(
        mangaChapterListProvider(mangaId: 1).future,
      );
      await details.entered.future;
      auth.epoch++;
      details.chapters.complete([]);
      expect(await pending, isNull);
      expect(sync.chapterWrites, 0);
      expect(details.sourceFetches, 0);
    },
  );
}
