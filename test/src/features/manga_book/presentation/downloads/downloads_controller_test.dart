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

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// Answers each queue fetch from a script, so a test can delay one response or
/// make it fail. The last entry repeats once the script runs out.
class _FakeRepo extends DownloadsRepository {
  _FakeRepo.scripted(this.responses) : super(_dummyClient(), _dummyClient());

  /// Mirrors `_maxReconcileFailures` in the controller.
  static const maxFailures = 3;

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
    'isDownloaded': false,
    '__typename': 'ChapterType',
  },
  'manga': {
    'id': 1,
    'title': 'Series',
    'downloadCount': 0,
    'thumbnailUrl': null,
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

    test('shows when every item has permanently failed', () async {
      // The old gate excluded items errored at tries == 3, hiding the control
      // for a wholly-failed queue — the case where restarting matters most.
      final container = await _silentFeed(
        _status('STOPPED', [
          _queueItem(chapterId: 10, position: 0, state: 'ERROR', tries: 3),
          _queueItem(chapterId: 11, position: 1, state: 'ERROR', tries: 3),
        ]),
      );

      expect(container.read(showDownloadsFABProvider), isTrue);
    });

    test('hides for an empty queue', () async {
      final container = await _silentFeed(_status('STOPPED', const []));
      expect(container.read(showDownloadsFABProvider), isFalse);
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
      expect(
        container.read(downloadsChapterIdsProvider),
        [10, 11, 12],
        reason: 'the re-read is applied, not discarded',
      );
      expect(
        seen,
        isNot(contains(0)),
        reason: 'the queue never went empty mid-reload',
      );
    });

    test('a progress tick does not outrank an in-flight re-read', () async {
      // The feed publishes roughly once a second while downloading. If those
      // ticks counted as changes, a round-trip slower than the tick rate could
      // never land and the queue would stay stale for good.
      final one = _queueItem(chapterId: 10, position: 0);
      final slow = Completer<DownloadStatusDto?>();
      final repo = _FakeRepo.scripted([
        () async => _status('STARTED', [one]),
        () => slow.future,
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

      feed.add(_feedMessage(omitted: true));
      await pumpEventQueue();

      feed.add(
        _feedMessage(
          updates: [
            {
              'type': 'PROGRESS',
              'download': _queueItem(chapterId: 10, position: 0),
              '__typename': 'DownloadUpdate',
            },
          ],
        ),
      );
      await pumpEventQueue();

      slow.complete(
        _status('STARTED', [one, _queueItem(chapterId: 11, position: 1)]),
      );
      await pumpEventQueue();

      expect(
        container.read(downloadsChapterIdsProvider),
        [10, 11],
        reason: 'the re-read still lands despite the progress tick',
      );
      expect(repo.fetches, 2, reason: 'no pointless second re-read');
    });

    test(
      'a progress tick that adds a chapter does outrank the re-read',
      () async {
        // PROGRESS is an upsert: a tick for a chapter we don't have adds it. That
        // is a membership change, so a snapshot taken before it must not win.
        final one = _queueItem(chapterId: 10, position: 0);
        final slow = Completer<DownloadStatusDto?>();
        final repo = _FakeRepo.scripted([
          () async => _status('STARTED', [one]),
          () => slow.future,
          () async =>
              _status('STARTED', [one, _queueItem(chapterId: 11, position: 1)]),
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

        feed.add(_feedMessage(omitted: true));
        await pumpEventQueue();

        feed.add(
          _feedMessage(
            updates: [
              {
                'type': 'PROGRESS',
                'download': _queueItem(chapterId: 11, position: 1),
                '__typename': 'DownloadUpdate',
              },
            ],
          ),
        );
        await pumpEventQueue();
        expect(container.read(downloadsChapterIdsProvider), [10, 11]);

        slow.complete(_status('STARTED', [one]));
        await pumpEventQueue();

        expect(
          container.read(downloadsChapterIdsProvider),
          [10, 11],
          reason: 'the older snapshot must not drop chapter 11 again',
        );
      },
    );

    test('a server that keeps refusing the read is left alone', () async {
      final repo = _FakeRepo.scripted([
        () async =>
            _status('STARTED', [_queueItem(chapterId: 10, position: 0)]),
        () async => throw Exception('server unreachable'),
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

      feed.add(_feedMessage(omitted: true));
      await pumpEventQueue();

      // Ten more messages would be ten more requests without a backoff. Half
      // report further dropped batches, which re-arm the need for a read but
      // must not be read as the server having recovered.
      for (var i = 0; i < 10; i++) {
        feed.add(_feedMessage(omitted: i.isEven));
        await pumpEventQueue();
      }

      expect(repo.fetches, greaterThan(1), reason: 'it does retry at first');
      expect(
        repo.fetches,
        lessThanOrEqualTo(1 + _FakeRepo.maxFailures),
        reason: 'but stops rather than issuing one per feed message',
      );
    });

    test(
      'a slow re-fetch cannot resurrect a chapter dequeued mid-flight',
      () async {
        // Refetch goes out holding [10, 11]; a DEQUEUED delta drops 11 while it
        // is still in the air. Applying the stale snapshot on arrival would put
        // 11 back — so the snapshot is discarded and the queue re-read.
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

        expect(
          container.read(downloadsChapterIdsProvider),
          [10],
          reason: 'the stale snapshot must not bring chapter 11 back',
        );
        expect(
          repo.fetches,
          3,
          reason: 'it re-reads instead of applying stale',
        );
      },
    );

    test('a failed re-fetch leaves the queue intact', () async {
      final repo = _FakeRepo.scripted([
        () async =>
            _status('STARTED', [_queueItem(chapterId: 10, position: 0)]),
        () async => throw Exception('server unreachable'),
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

      feed.add(_feedMessage(omitted: true));
      await pumpEventQueue();

      // No unhandled async error, and the last known queue survives.
      expect(repo.fetches, 2, reason: 'the re-fetch was attempted');
      expect(container.read(downloadsChapterIdsProvider), [10]);
    });

    test('a reorder mid-flight is not undone by the re-fetch', () async {
      // reorder writes the queue without a rebuild, so its write is the one
      // the generation counter has to catch on its own.
      final both = [
        _queueItem(chapterId: 10, position: 0),
        _queueItem(chapterId: 11, position: 1),
      ];
      final swapped = [
        _queueItem(chapterId: 11, position: 0),
        _queueItem(chapterId: 10, position: 1),
      ];
      final slow = Completer<DownloadStatusDto?>();
      final repo = _FakeRepo.scripted([
        () async => _status('STARTED', both),
        () => slow.future,
        () async => _status('STARTED', swapped),
      ])..reorderResult = _status('STARTED', swapped);
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

      container.read(downloadsMapProvider.notifier).reorder(11, 0);
      await pumpEventQueue();
      expect(container.read(downloadsChapterIdsProvider), [11, 10]);

      slow.complete(_status('STARTED', both));
      await pumpEventQueue();

      expect(
        container.read(downloadsChapterIdsProvider),
        [11, 10],
        reason: 'the stale snapshot must not undo the reorder',
      );
    });

    test(
      'clearing the queue mid-flight is not undone by the re-fetch',
      () async {
        // #73 all over again if this breaks: the user empties the queue, the
        // in-flight snapshot lands, and all of it comes back. (clearAll also
        // invalidates the status query, so the rebuild guards this too.)
        final both = [
          _queueItem(chapterId: 10, position: 0),
          _queueItem(chapterId: 11, position: 1),
        ];
        final slow = Completer<DownloadStatusDto?>();
        final repo = _FakeRepo.scripted([
          () async => _status('STARTED', both),
          () => slow.future,
          () async => _status('STOPPED', const []),
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

        feed.add(_feedMessage(omitted: true));
        await pumpEventQueue();

        await container.read(downloadsMapProvider.notifier).clearAll();
        await pumpEventQueue();
        expect(container.read(downloadsChapterIdsProvider), isEmpty);

        slow.complete(_status('STARTED', both));
        await pumpEventQueue();

        expect(
          container.read(downloadsChapterIdsProvider),
          isEmpty,
          reason: 'the cleared queue must stay cleared',
        );
      },
    );
  });

  group('downloaderRunState', () {
    test('falls back to the queue query when the feed is silent', () async {
      final container = await _silentFeed(
        _status('STOPPED', [_queueItem(chapterId: 10, position: 0)]),
      );

      expect(
        container.read(downloaderRunStateProvider),
        DownloaderState.STOPPED,
      );
    });

    test('prefers the live feed once it speaks', () async {
      final container = ProviderContainer(
        overrides: [
          // Query says stopped, feed says started: the feed is newer.
          downloadStatusProvider.overrideWith(
            (ref) => Future.value(_status('STOPPED', const [])),
          ),
          downloadUpdatesProvider.overrideWith(
            (ref) => Stream.value(
              DownloadUpdatesDto.fromJson({
                'state': 'STARTED',
                'omittedUpdates': false,
                'updates': const [],
                'initial': const [],
                '__typename': 'DownloadUpdates',
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Hold both alive across the awaits; they're autoDispose, and in the app
      // the screen is what keeps them subscribed.
      container.listen(downloadUpdatesProvider, (_, _) {});
      container.listen(downloaderRunStateProvider, (_, _) {});
      await container.read(downloadStatusProvider.future);
      await container.read(downloadUpdatesProvider.future);

      expect(
        container.read(downloaderRunStateProvider),
        DownloaderState.STARTED,
      );
    });
  });
}
