// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tsumiru/src/features/offline/data/chapter_manifest.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';

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

      // An incomplete chapter never becomes partly visible.
      await store.beginChapter(
        552,
        2001,
        const ChapterManifest(generation: 0, indices: [0, 1]),
      );
      await store.writePage(552, 2001, 0, [1, 2], 'jpg');
      expect(await store.commitStaging(552, 2001), isNull);
      expect(
        await Directory(p.join(tmp.path, '552', '2001')).exists(),
        isFalse,
      );
    },
  );

  test(
    'a set-aside copy is restored, and a live chapter is never overwritten',
    () async {
      await store.beginChapter(
        9,
        905,
        const ChapterManifest(generation: 0, indices: [0]),
      );
      await store.writePage(9, 905, 0, [4, 5, 6], 'jpg');
      await store.commitStaging(9, 905);
      await Directory(
        p.join(tmp.path, '9', '905'),
      ).rename(p.join(tmp.path, '9', '905.superseded'));

      final found = await store.chaptersOnDisk();
      expect(found.single.hasFinal, isFalse);
      expect(found.single.hasSuperseded, isTrue);

      expect(await store.restoreSuperseded(9, 905), isTrue);
      expect(
        await File(p.join(tmp.path, '9', '905', '000.jpg')).readAsBytes(),
        [4, 5, 6],
      );
      expect(
        (await store.inspectCommitted(9, 905)).state,
        ChapterDirState.complete,
      );

      await store.beginChapter(
        9,
        906,
        const ChapterManifest(generation: 0, indices: [0]),
      );
      await store.writePage(9, 906, 0, [7], 'jpg');
      await store.commitStaging(9, 906);
      await Directory(
        p.join(tmp.path, '9', '906.superseded'),
      ).create(recursive: true);

      expect(await store.restoreSuperseded(9, 906), isFalse);
      expect(
        await File(p.join(tmp.path, '9', '906', '000.jpg')).readAsBytes(),
        [7],
      );
    },
  );
}
