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
}
