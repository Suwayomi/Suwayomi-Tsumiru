import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import 'chapter_test_helpers.dart';

class _SessionStore extends AuthCredentialsStore {
  int epoch = 0;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState();
}

class _ChapterList extends MangaChapterList {
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => [
    ch(id: 1, number: 1),
  ];
}

class _DelayedRepository extends MangaBookRepository {
  _DelayedRepository()
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
      );
  final entered = Completer<void>();
  final response = Completer<List<ChapterDto>?>();
  int sourceRequests = 0;
  @override
  Future<List<ChapterDto>?> getStoredChapterList(int mangaId) {
    entered.complete();
    return response.future;
  }

  @override
  Future<List<ChapterDto>?> getMangaAndChapterList(int mangaId) async {
    sourceRequests++;
    return [ch(id: 3, number: 3)];
  }
}

void main() {
  test(
    'account replacement discards refresh and skips follow-up source fetch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = _SessionStore();
      final repo = _DelayedRepository();
      final provider = mangaChapterListProvider(mangaId: 1);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authCredentialsStoreProvider.overrideWith(() => auth),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          offlineSyncProvider.overrideWithValue(null),
          offlineReadDatabaseProvider.overrideWithValue(null),
          provider.overrideWith(_ChapterList.new),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final pending = container.read(provider.notifier).refresh(true);
      await repo.entered.future;
      auth.epoch++;
      repo.response.complete([ch(id: 2, number: 2)]);
      await pending;
      expect(repo.sourceRequests, 0);
      expect(container.read(provider).value!.map((chapter) => chapter.id), [1]);
    },
  );
}
