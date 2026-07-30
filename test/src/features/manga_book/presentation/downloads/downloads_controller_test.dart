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

/// Serves a canned queue and counts how often it was asked for one.
class _FakeRepo extends DownloadsRepository {
  _FakeRepo(this.status) : super(_dummyClient(), _dummyClient());

  final DownloadStatusDto status;
  int fetches = 0;

  @override
  Future<DownloadStatusDto?> getDownloadStatus() async {
    fetches++;
    return status;
  }
}

Map<String, dynamic> _queueItem({
  required int chapterId,
  required int position,
  String state = 'QUEUED',
  int tries = 0,
}) =>
    {
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
) =>
    DownloadStatusDto.fromJson({
      'state': downloaderState,
      'queue': queue,
      '__typename': 'DownloadStatus',
    });

/// A container where the live download feed never speaks — the real shape when
/// the queue is paused (nothing changes, so no deltas) or when the server drops
/// updates under a mass enqueue.
Future<ProviderContainer> _silentFeed(DownloadStatusDto status) async {
  final container = ProviderContainer(overrides: [
    downloadStatusProvider.overrideWith((ref) => Future.value(status)),
    downloadUpdatesProvider
        .overrideWith((ref) => const Stream<DownloadUpdatesDto?>.empty()),
  ]);
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
      final container = await _silentFeed(_status('STOPPED', [
        _queueItem(chapterId: 10, position: 0),
        _queueItem(chapterId: 11, position: 1),
      ]));

      expect(container.read(downloadsChapterIdsProvider), [10, 11]);
      expect(container.read(showDownloadsFABProvider), isTrue);
    });

    test('shows when every item has permanently failed', () async {
      // The old gate excluded items errored at tries == 3, hiding the control
      // for a wholly-failed queue — the case where restarting matters most.
      final container = await _silentFeed(_status('STOPPED', [
        _queueItem(chapterId: 10, position: 0, state: 'ERROR', tries: 3),
        _queueItem(chapterId: 11, position: 1, state: 'ERROR', tries: 3),
      ]));

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
      final status = _status('STARTED', [
        _queueItem(chapterId: 10, position: 0),
        _queueItem(chapterId: 11, position: 1),
      ]);
      final repo = _FakeRepo(status);
      final feed = StreamController<DownloadUpdatesDto?>();
      addTearDown(feed.close);

      final container = ProviderContainer(overrides: [
        downloadsRepositoryProvider.overrideWithValue(repo),
        downloadUpdatesProvider.overrideWith((ref) => feed.stream),
      ]);
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

      feed.add(DownloadUpdatesDto.fromJson({
        'state': 'STARTED',
        'omittedUpdates': true,
        'updates': const [],
        'initial': null,
        '__typename': 'DownloadUpdates',
      }));
      await pumpEventQueue();

      expect(repo.fetches, 2, reason: 'the dropped batch forces a re-fetch');
      expect(container.read(downloadsChapterIdsProvider), [10, 11]);
      expect(seen, isNot(contains(0)),
          reason: 'the queue never went empty mid-reload');
    });
  });

  group('downloaderRunState', () {
    test('falls back to the queue query when the feed is silent', () async {
      final container = await _silentFeed(_status('STOPPED', [
        _queueItem(chapterId: 10, position: 0),
      ]));

      expect(container.read(downloaderRunStateProvider),
          DownloaderState.STOPPED);
    });

    test('prefers the live feed once it speaks', () async {
      final container = ProviderContainer(overrides: [
        // Query says stopped, feed says started: the feed is newer.
        downloadStatusProvider.overrideWith(
            (ref) => Future.value(_status('STOPPED', const []))),
        downloadUpdatesProvider.overrideWith((ref) =>
            Stream.value(DownloadUpdatesDto.fromJson({
              'state': 'STARTED',
              'omittedUpdates': false,
              'updates': const [],
              'initial': const [],
              '__typename': 'DownloadUpdates',
            }))),
      ]);
      addTearDown(container.dispose);
      // Hold both alive across the awaits; they're autoDispose, and in the app
      // the screen is what keeps them subscribed.
      container.listen(downloadUpdatesProvider, (_, _) {});
      container.listen(downloaderRunStateProvider, (_, _) {});
      await container.read(downloadStatusProvider.future);
      await container.read(downloadUpdatesProvider.future);

      expect(container.read(downloaderRunStateProvider),
          DownloaderState.STARTED);
    });
  });
}
