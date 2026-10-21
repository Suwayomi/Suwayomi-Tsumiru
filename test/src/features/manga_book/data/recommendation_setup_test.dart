import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/recommendations/recommendation_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/tracking/controller/manga_track_records_controller.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';

import '../reader/reader_test_fixtures.dart';

Fragment$TrackRecordDto _record(String remoteId) => Fragment$TrackRecordDto(
  id: 1,
  trackerId: 1,
  remoteId: remoteId,
  title: 'Example',
  remoteUrl: 'https://example.test',
  status: 0,
  lastChapterRead: 0,
  totalChapters: 0,
  score: 0,
  displayScore: '',
  startDate: '',
  finishDate: '',
  private: false,
);

class _Manga extends MangaWithId {
  _Manga(this.manga);
  final Fragment$MangaDto manga;
  @override
  Future<Fragment$MangaDto?> build({required int mangaId}) async => manga;
}

void main() {
  test(
    'setup follows authoritative tracker relinking and unlinking while manga DTO stays cached',
    () async {
      final manga = testManga().copyWith(
        trackRecords: Fragment$MangaDto$trackRecords(
          nodes: [
            Fragment$MangaDto$trackRecords$nodes(
              id: 1,
              trackerId: 1,
              remoteId: '1',
              status: 0,
              score: 0,
              title: 'Example',
            ),
          ],
        ),
      );
      var records = [_record('1')];
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          mangaWithIdProvider(mangaId: 1).overrideWith(() => _Manga(manga)),
          trackersProvider.overrideWith(
            (ref) async => [
              Fragment$TrackerDto(
                id: 1,
                name: 'MangaUpdates',
                icon: '',
                isLoggedIn: true,
                isTokenExpired: false,
                supportsTrackDeletion: true,
                supportsPrivateTracking: false,
                supportsReadingDates: false,
                scores: const [],
                statuses: const [],
              ),
            ],
          ),
          mangaTrackRecordsProvider(
            mangaId: 1,
          ).overrideWith((ref) async => records),
        ],
      );
      addTearDown(container.dispose);
      container.listen(recommendationSetupProvider(1), (_, _) {});
      expect(
        (await container.read(
          recommendationSetupProvider(1).future,
        ))?.ctx.remoteIdByTracker,
        {'mangaupdates': '1'},
      );
      records = [_record('2')];
      container.invalidate(mangaTrackRecordsProvider(mangaId: 1));
      await container.pump();
      expect(
        (await container.read(
          recommendationSetupProvider(1).future,
        ))?.ctx.remoteIdByTracker,
        {'mangaupdates': '2'},
      );
      records = [];
      container.invalidate(mangaTrackRecordsProvider(mangaId: 1));
      await container.pump();
      expect(
        (await container.read(
          recommendationSetupProvider(1).future,
        ))?.ctx.remoteIdByTracker,
        isEmpty,
      );
      expect(
        await container.read(mangaWithIdProvider(mangaId: 1).future),
        same(manga),
      );
    },
  );
}
