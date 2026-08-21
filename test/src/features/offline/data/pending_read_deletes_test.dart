// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

ChapterDto _ch(int id, {required int sourceOrder, bool isRead = false}) =>
    Fragment$ChapterDto(
      id: id,
      mangaId: 1,
      name: 'c$id',
      chapterNumber: id.toDouble(),
      sourceOrder: sourceOrder,
      scanlator: null,
      isRead: isRead,
      isBookmarked: false,
      isDownloaded: true,
      lastPageRead: 0,
      pageCount: 10,
      fetchedAt: '0',
      uploadDate: '0',
      lastReadAt: '0',
      url: '',
      meta: const <Fragment$ChapterDto$meta>[],
    );

class _FixedChapterList extends MangaChapterList {
  _FixedChapterList(this.chapters);
  final List<ChapterDto> chapters;

  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => chapters;
}

void main() {
  test('while-reading deletes queue up and drain once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final pending = container.read(pendingReadDeletesProvider.notifier);

    const entry = (mangaId: 1, chapterId: 10, server: false);
    pending.enqueue(entry);
    pending.enqueue((mangaId: 1, chapterId: 11, server: true));
    // Finishing the same chapter twice (re-read after scroll-back) must not
    // queue a second delete.
    pending.enqueue(entry);

    expect(container.read(pendingReadDeletesProvider), hasLength(2));
    expect(pending.drain(), hasLength(2));
    // Drained: the reader-exit flush must not run these twice.
    expect(pending.drain(), isEmpty);
  });

  test('session-read set accumulates without draining', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = container.read(sessionReadChaptersProvider.notifier);

    session.record(10);
    session.record(11);
    session.record(10);

    expect(container.read(sessionReadChaptersProvider), {10, 11});
  });

  test('discard removes specified chapter IDs from session set', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = container.read(sessionReadChaptersProvider.notifier);

    session.record(10);
    session.record(11);
    session.record(12);
    expect(container.read(sessionReadChaptersProvider), {10, 11, 12});

    // Discarding a subset leaves the rest intact.
    session.discard({10, 12});
    expect(container.read(sessionReadChaptersProvider), {11});

    // Discarding IDs absent from the set is a no-op.
    session.discard({99});
    expect(container.read(sessionReadChaptersProvider), {11},
        reason: 'unknown id must not mutate state');

    // Discarding empty set is a no-op.
    session.discard({});
    expect(container.read(sessionReadChaptersProvider), {11});
  });

  testWidgets(
      'finishing a chapter queues the RESOLVED delete target, not the finished '
      'chapter', (tester) async {
    final (captured, container) = await _pumpFinishHarness(tester);

    await noteChapterFinishedInReader(captured, mangaId: 1, chapterId: 3);

    expect(container.read(sessionReadChaptersProvider), isEmpty,
        reason: 'noteChapterFinishedInReader no longer records session '
            'protection — the reader widget does that via its open/close hooks');
    final queued = container.read(pendingReadDeletesProvider);
    expect(queued.where((p) => !p.server).map((p) => p.chapterId), [2],
        reason: 'the device delete stores the resolved 2-slots-back target');
  });

  testWidgets('exit flush waits for a resolution still in flight',
      (tester) async {
    final (captured, container) = await _pumpFinishHarness(tester);

    // Deliberately NOT awaited — the reader's call sites fire and forget, and
    // exiting right after a finish must not strand the late entry.
    final resolution =
        noteChapterFinishedInReader(captured, mangaId: 1, chapterId: 3);
    await flushPendingReadDeletes(container);

    expect(container.read(pendingReadDeletesProvider), isEmpty,
        reason: 'the flush drained the entry the resolution added, so nothing '
            'is left for a future session');
    await resolution;
    expect(container.read(pendingReadDeletesProvider), isEmpty,
        reason: 'nothing lands after the flush that waited');
  });
}

/// Chapters 1..3 in reading order, delete-while-reading at 2 slots, offline
/// active: finishing chapter 3 resolves a device delete for chapter 2.
Future<(WidgetRef, ProviderContainer)> _pumpFinishHarness(
    WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final chapters = [
    _ch(3, sourceOrder: 3),
    _ch(2, sourceOrder: 2, isRead: true),
    _ch(1, sourceOrder: 1, isRead: true),
  ];

  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineActiveProvider.overrideWithValue(true),
        localDeleteSettingsProvider.overrideWithValue(
          const DeleteChaptersSettings(
            deleteWhileReading: 2,
            deleteManuallyMarkedRead: false,
            deleteWithBookmark: false,
          ),
        ),
        mangaChapterListProvider(mangaId: 1)
            .overrideWith(() => _FixedChapterList(chapters)),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox();
        },
      ),
    ),
  );
  final container =
      ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
  return (captured, container);
}
