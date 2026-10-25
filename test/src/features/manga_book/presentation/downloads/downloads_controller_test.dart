// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/downloads/downloads_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/downloads_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads_queue/downloads_queue_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';

import '../../../../../helpers/legacy_account_access.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// Answers each queue fetch from a script, so a test can delay one response or
/// make it fail. The last entry repeats once the script runs out.
class _FakeRepo extends DownloadsRepository {
  _FakeRepo.scripted(this.responses)
    : super(
        _dummyClient(),
        _dummyClient(),
        permissions: legacyAccountPermissions,
      );

  final List<Future<DownloadStatusDto?> Function()> responses;
  int fetches = 0;

  @override
  Future<DownloadStatusDto?> getDownloadStatus() {
    final response = responses[fetches.clamp(0, responses.length - 1)];
    fetches++;
    return response();
  }

  @override
  Future<void> clearDownloads() async {}

  DownloadStatusDto? reorderResult;

  @override
  Future<DownloadStatusDto?> reorderDownload(int chapterId, int to) async =>
      reorderResult;
}

Map<String, dynamic> _dequeued(Map<String, dynamic> item) => {
  'type': 'DEQUEUED',
  'download': item,
  '__typename': 'DownloadUpdate',
};

DownloadUpdatesDto _feedMessage({
  bool omitted = false,
  List<Map<String, dynamic>> updates = const [],
}) => DownloadUpdatesDto.fromJson({
  'state': 'STARTED',
  'omittedUpdates': omitted,
  'updates': updates,
  'initial': null,
  '__typename': 'DownloadUpdates',
});

Map<String, dynamic> _queueItem({
  required int chapterId,
  required int position,
  String state = 'QUEUED',
  int tries = 0,
}) => {
  'chapter': {
    'id': chapterId,
    'name': 'Ch. $chapterId',
    'sourceOrder': position,
    'user': {'isDownloaded': false, '__typename': 'ChapterUserType'},
    'pageCount': 0,
    '__typename': 'ChapterType',
  },
  'manga': {
    'id': 1,
    'title': 'Series',
    'user': {
      'downloadCount': 0,
      'inLibrary': true,
      '__typename': 'MangaUserType',
    },
    'thumbnailUrl': null,
    'source': null,
    '__typename': 'MangaType',
  },
  'progress': 0.0,
  'state': state,
  'tries': tries,
  'position': position,
  '__typename': 'DownloadType',
};

DownloadStatusDto _status(
  String downloaderState,
  List<Map<String, dynamic>> queue,
) => DownloadStatusDto.fromJson({
  'state': downloaderState,
  'queue': queue,
  '__typename': 'DownloadStatus',
});

/// A container where the live download feed never speaks — the real shape when
/// the queue is paused (nothing changes, so no deltas) or when the server drops
/// updates under a mass enqueue.
Future<ProviderContainer> _silentFeed(DownloadStatusDto status) async {
  final container = ProviderContainer(
    overrides: [
      downloadStatusProvider.overrideWith((ref) => Future.value(status)),
      downloadUpdatesProvider.overrideWith(
        (ref) => const Stream<DownloadUpdatesDto?>.empty(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(downloadStatusProvider.future);
  return container;
}

void main() {
  group('showDownloadsFAB', () {
    test('shows for a queue the live feed has said nothing about', () async {
      // The regression (#313): the queue arrives via the subscription's
      // `initial` snapshot with an empty delta list, and the old gate read only
      // the deltas — so a paused queue rendered rows with no way to restart it.
      final container = await _silentFeed(
        _status('STOPPED', [
          _queueItem(chapterId: 10, position: 0),
          _queueItem(chapterId: 11, position: 1),
        ]),
      );

      expect(container.read(downloadsChapterIdsProvider), [10, 11]);
      expect(container.read(showDownloadsFABProvider), isTrue);
    });
  });

  group('omitted updates', () {
    test('re-fetches the queue without blanking it', () async {
      // The server drops deltas past `maxUpdates` on a mass enqueue and expects
      // a re-fetch. The queue must survive that reload — an empty frame would
      // take the control down with it, which is the bug all over again.
      // The re-read returns a queue that has moved on, so the assertions can
      // tell "applied" apart from "fetched and thrown away".
      final repo = _FakeRepo.scripted([
        () async => _status('STARTED', [
          _queueItem(chapterId: 10, position: 0),
          _queueItem(chapterId: 11, position: 1),
        ]),
        () async => _status('STARTED', [
          _queueItem(chapterId: 10, position: 0),
          _queueItem(chapterId: 11, position: 1),
          _queueItem(chapterId: 12, position: 2),
        ]),
      ]);
      final feed = StreamController<DownloadUpdatesDto?>();
      addTearDown(feed.close);

      final container = ProviderContainer(
        overrides: [
          downloadsRepositoryProvider.overrideWithValue(repo),
          downloadUpdatesProvider.overrideWith((ref) => feed.stream),
        ],
      );
      addTearDown(container.dispose);

      container.listen(downloadsChapterIdsProvider, (_, _) {});
      await container.read(downloadStatusProvider.future);
      expect(container.read(downloadsChapterIdsProvider), [10, 11]);
      expect(repo.fetches, 1);

      // Record every queue length published from here on: the reload must not
      // pass through an empty frame.
      final seen = <int>[];
      container.listen(
        downloadsChapterIdsProvider,
        (_, next) => seen.add(next.length),
      );

      feed.add(
        DownloadUpdatesDto.fromJson({
          'state': 'STARTED',
          'omittedUpdates': true,
          'updates': const [],
          'initial': null,
          '__typename': 'DownloadUpdates',
        }),
      );
      await pumpEventQueue();

      expect(repo.fetches, 2, reason: 'the dropped batch forces a re-fetch');
      expect(container.read(downloadsChapterIdsProvider), [
        10,
        11,
        12,
      ], reason: 'the re-read is applied, not discarded');
      expect(
        seen,
        isNot(contains(0)),
        reason: 'the queue never went empty mid-reload',
      );
    });

    test(
      'a stale snapshot cannot resurrect a dequeued chapter or undo a clear',
      () async {
        final both = [
          _queueItem(chapterId: 10, position: 0),
          _queueItem(chapterId: 11, position: 1),
        ];
        final slow = Completer<DownloadStatusDto?>();
        final repo = _FakeRepo.scripted([
          () async => _status('STARTED', both),
          () => slow.future,
          () async => _status('STARTED', [both.first]),
        ]);
        final feed = StreamController<DownloadUpdatesDto?>();
        addTearDown(feed.close);

        final container = ProviderContainer(
          overrides: [
            downloadsRepositoryProvider.overrideWithValue(repo),
            downloadUpdatesProvider.overrideWith((ref) => feed.stream),
          ],
        );
        addTearDown(container.dispose);
        container.listen(downloadsChapterIdsProvider, (_, _) {});
        await container.read(downloadStatusProvider.future);
        expect(container.read(downloadsChapterIdsProvider), [10, 11]);

        feed.add(_feedMessage(omitted: true));
        await pumpEventQueue();
        expect(repo.fetches, 2, reason: 'the re-fetch is in flight');

        feed.add(_feedMessage(updates: [_dequeued(both[1])]));
        await pumpEventQueue();
        expect(container.read(downloadsChapterIdsProvider), [10]);

        slow.complete(_status('STARTED', both));
        await pumpEventQueue();

        expect(container.read(downloadsChapterIdsProvider), [
          10,
        ], reason: 'the stale snapshot must not bring chapter 11 back');
        expect(
          repo.fetches,
          3,
          reason: 'it re-reads instead of applying stale',
        );

        // The same guard covers a queue cleared mid-flight.
        final clearedBoth = [
          _queueItem(chapterId: 10, position: 0),
          _queueItem(chapterId: 11, position: 1),
        ];
        final slowClear = Completer<DownloadStatusDto?>();
        final clearedRepo = _FakeRepo.scripted([
          () async => _status('STARTED', clearedBoth),
          () => slowClear.future,
          () async => _status('STOPPED', const []),
        ]);
        final clearedFeed = StreamController<DownloadUpdatesDto?>();
        addTearDown(clearedFeed.close);
        final cleared = ProviderContainer(
          overrides: [
            downloadsRepositoryProvider.overrideWithValue(clearedRepo),
            downloadUpdatesProvider.overrideWith((ref) => clearedFeed.stream),
          ],
        );
        addTearDown(cleared.dispose);
        cleared.listen(downloadsChapterIdsProvider, (_, _) {});
        await cleared.read(downloadStatusProvider.future);

        clearedFeed.add(_feedMessage(omitted: true));
        await pumpEventQueue();

        await cleared.read(downloadsMapProvider.notifier).clearAll();
        await pumpEventQueue();
        expect(cleared.read(downloadsChapterIdsProvider), isEmpty);

        slowClear.complete(_status('STARTED', clearedBoth));
        await pumpEventQueue();

        expect(
          cleared.read(downloadsChapterIdsProvider),
          isEmpty,
          reason: 'the cleared queue must stay cleared',
        );
      },
    );
  });
}
