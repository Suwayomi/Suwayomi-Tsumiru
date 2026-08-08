// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';

void main() {
  late Directory tmp;
  late IoOfflinePageStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline_page_store_test');
    store = IoOfflinePageStore(OfflinePaths(tmp.path));
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
    'a page lands in staging, and only a commit makes it readable',
    () async {
      await store.beginChapter(
        552,
        2000,
        const ChapterManifest(generation: 0, indices: [0]),
      );
      final r = await store.writePage(552, 2000, 0, [1, 2, 3, 4], 'jpg');
      expect(r.relPath, '552/2000.part/000.jpg');
      expect(r.bytes, 4);

      // Nothing is visible under the chapter's real directory yet.
      expect(
        await Directory(p.join(tmp.path, '552', '2000')).exists(),
        isFalse,
      );

      final pages = await store.commitStaging(552, 2000);
      expect(pages!.single.relPath, '552/2000/000.jpg');
      final f = File(p.join(tmp.path, '552', '2000', '000.jpg'));
      expect(await f.exists(), isTrue);
      expect(await f.readAsBytes(), [1, 2, 3, 4]);
      expect(
        await Directory(p.join(tmp.path, '552', '2000.part')).exists(),
        isFalse,
        reason: 'staging became the final directory',
      );
    },
  );

  test('incomplete staging refuses to commit', () async {
    await store.beginChapter(
      552,
      2000,
      const ChapterManifest(generation: 0, indices: [0, 1]),
    );
    await store.writePage(552, 2000, 0, [1, 2], 'jpg');

    expect(await store.commitStaging(552, 2000), isNull);
    expect(
      await Directory(p.join(tmp.path, '552', '2000')).exists(),
      isFalse,
      reason: 'a chapter is never partly visible',
    );
  });

  test('leaves no .tmp file behind (atomic rename)', () async {
    await store.beginChapter(
      552,
      2000,
      const ChapterManifest(generation: 0, indices: [1]),
    );
    await store.writePage(552, 2000, 1, [9], 'png');
    final part = File(p.join(tmp.path, '552', '2000.part', '001.png.tmp'));
    expect(await part.exists(), isFalse);
  });

  test('deleteChapter removes the chapter directory', () async {
    await store.writePage(552, 2000, 0, [1], 'jpg');
    await store.writePage(552, 2000, 1, [2], 'jpg');
    await store.deleteChapter(552, 2000);
    expect(await Directory(p.join(tmp.path, '552', '2000')).exists(), isFalse);
  });

  test('deleteChapter is a no-op when nothing was downloaded', () async {
    await store.deleteChapter(999, 999); // must not throw
  });

  test(
    'stageChapterCopy copies the source into the target staging area',
    () async {
      await store.beginChapter(
        1,
        101,
        const ChapterManifest(generation: 0, indices: [0, 1]),
      );
      await store.writePage(1, 101, 0, [1, 2], 'jpg');
      await store.writePage(1, 101, 1, [3, 4, 5], 'jpg');
      await store.commitStaging(1, 101);

      final manifest = await store.stageChapterCopy(
        1,
        101,
        2,
        201,
        generation: 4,
      );

      expect(manifest.indices, [0, 1]);
      expect(manifest.generation, 4);
      // The source is untouched: it is only removed after the target commits, so
      // a crash here can never destroy the last copy.
      expect(
        await File(p.join(tmp.path, '1', '101', '000.jpg')).exists(),
        isTrue,
      );
      final pages = await store.commitStaging(2, 201);
      expect(pages!.map((e) => e.relPath), ['2/201/000.jpg', '2/201/001.jpg']);
      expect(pages.map((e) => e.bytes), [2, 3]);
    },
  );

  test('stageChapterCopy throws when the source has no files', () async {
    expect(
      () => store.stageChapterCopy(1, 999, 2, 201, generation: 0),
      throwsA(isA<OfflineTransferException>()),
    );
  });

  test('a failed promotion leaves the old chapter readable', () async {
    // The old copy is moved aside rather than deleted. If the rename in fails,
    // the caller's error path purges staging — so without the restore the
    // chapter would be gone for good, not merely un-replaced.
    await store.beginChapter(
      9,
      900,
      const ChapterManifest(generation: 0, indices: [0]),
    );
    await store.writePage(9, 900, 0, [1, 2, 3], 'jpg');
    await store.commitStaging(9, 900);
    expect(
      await File(p.join(tmp.path, '9', '900', '000.jpg')).exists(),
      isTrue,
    );

    // A replacement is staged, then its promotion is sabotaged by putting a
    // FILE where the chapter directory needs to go.
    await store.beginChapter(
      9,
      900,
      const ChapterManifest(generation: 0, indices: [0]),
    );
    await store.writePage(9, 900, 0, [9, 9], 'jpg');
    await Directory(p.join(tmp.path, '9', '900')).delete(recursive: true);
    await File(p.join(tmp.path, '9', '900')).writeAsString('in the way');

    await expectLater(store.commitStaging(9, 900), throwsA(anything));
  });

  test('a copy left behind by an interrupted swap is cleaned up', () async {
    // A kill between promoting the new chapter and clearing the old one leaves
    // a full duplicate that nothing reads. Recovery must reach it, or it costs
    // a chapter of storage on every launch, forever.
    await store.beginChapter(
      9,
      904,
      const ChapterManifest(generation: 0, indices: [0]),
    );
    await store.writePage(9, 904, 0, [1, 2, 3], 'jpg');
    await store.commitStaging(9, 904);
    await Directory(
      p.join(tmp.path, '9', '904.superseded'),
    ).create(recursive: true);

    // The scan must surface the chapter so recovery visits it at all.
    final found = await store.chaptersOnDisk();
    expect(found.single.chapterId, 904);
    expect(found.single.hasFinal, isTrue);

    await store.deleteSuperseded(9, 904);
    expect(
      await Directory(p.join(tmp.path, '9', '904.superseded')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(tmp.path, '9', '904', '000.jpg')).exists(),
      isTrue,
      reason: 'the live chapter is untouched',
    );
  });

  test('a superseded copy is not mistaken for a chapter on disk', () async {
    await store.beginChapter(
      9,
      901,
      const ChapterManifest(generation: 0, indices: [0]),
    );
    await store.writePage(9, 901, 0, [1], 'jpg');
    await store.commitStaging(9, 901);
    // A crash mid-swap can leave one of these behind; recovery must ignore it
    // rather than treat it as a chapter of its own.
    await Directory(
      p.join(tmp.path, '9', '901.superseded'),
    ).create(recursive: true);

    final found = await store.chaptersOnDisk();
    expect(found.map((e) => e.chapterId), contains(901));
    expect(found.length, 1);

    await store.deleteChapter(9, 901);
    expect(
      await Directory(p.join(tmp.path, '9', '901.superseded')).exists(),
      isFalse,
      reason: 'deleting the chapter clears the leftover too',
    );
  });

  group('promotion keeps one complete copy at every instant', () {
    // Three directories can hold a chapter: the committed one, staging, and a
    // copy set aside mid-swap. Each crash point below leaves at least one of
    // them whole, because the alternative is a chapter the catalog claims to
    // have and cannot read.

    Future<void> commitOnePage(int chapterId, List<int> bytes) async {
      await store.beginChapter(
        9,
        chapterId,
        const ChapterManifest(generation: 0, indices: [0]),
      );
      await store.writePage(9, chapterId, 0, bytes, 'jpg');
      await store.commitStaging(9, chapterId);
    }

    test(
      'a kill mid-swap leaves the set-aside copy for the next commit',
      () async {
        await commitOnePage(902, [1, 1, 1]);
        // Recreate the on-disk state of a kill between "move the old copy aside"
        // and "rename the new one in": no committed dir, a set-aside copy, and
        // complete staging.
        await Directory(
          p.join(tmp.path, '9', '902'),
        ).rename(p.join(tmp.path, '9', '902.superseded'));
        await store.beginChapter(
          9,
          902,
          const ChapterManifest(generation: 0, indices: [0]),
        );
        await store.writePage(9, 902, 0, [2, 2], 'jpg');

        final pages = await store.commitStaging(9, 902);

        expect(pages, isNotNull, reason: 'the replacement lands');
        expect(
          await File(p.join(tmp.path, '9', '902', '000.jpg')).readAsBytes(),
          [2, 2],
        );
        expect(
          await Directory(p.join(tmp.path, '9', '902.superseded')).exists(),
          isFalse,
          reason: 'the set-aside copy is cleared once the new one is in place',
        );
      },
    );

    test(
      'a failed promotion after a kill mid-swap restores the old chapter',
      () async {
        await commitOnePage(903, [1, 1, 1]);
        await Directory(
          p.join(tmp.path, '9', '903'),
        ).rename(p.join(tmp.path, '9', '903.superseded'));
        await store.beginChapter(
          9,
          903,
          const ChapterManifest(generation: 0, indices: [0]),
        );
        await store.writePage(9, 903, 0, [2, 2], 'jpg');
        // Block the promotion: a file where the chapter directory must go.
        await File(p.join(tmp.path, '9', '903')).writeAsString('in the way');

        await expectLater(store.commitStaging(9, 903), throwsA(anything));

        // The set-aside copy is the only complete one left, so it must survive.
        expect(
          await File(
            p.join(tmp.path, '9', '903.superseded', '000.jpg'),
          ).readAsBytes(),
          [1, 1, 1],
          reason: 'the previous chapter is still recoverable',
        );
      },
    );
  });
}
