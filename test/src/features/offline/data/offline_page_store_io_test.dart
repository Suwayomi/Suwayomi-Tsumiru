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

  test('writes a page to <mangaId>/<chapterId>/<NNN>.<ext> and reads back', () async {
    final r = await store.writePage(552, 2000, 0, [1, 2, 3, 4], 'jpg');
    expect(r.relPath, '552/2000/000.jpg');
    expect(r.bytes, 4);

    final f = File(p.join(tmp.path, '552', '2000', '000.jpg'));
    expect(await f.exists(), isTrue);
    expect(await f.readAsBytes(), [1, 2, 3, 4]);
  });

  test('leaves no .part file behind (atomic rename)', () async {
    await store.writePage(552, 2000, 1, [9], 'png');
    final part = File(p.join(tmp.path, '552', '2000', '001.png.part'));
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

  test('transferChapter MOVES files onto the target and empties the source',
      () async {
    await store.writePage(1, 101, 0, [1, 2], 'jpg');
    await store.writePage(1, 101, 1, [3, 4, 5], 'jpg');
    final pages = await store.transferChapter(1, 101, 2, 201, keepSource: false);
    expect(pages.map((p) => p.relPath),
        ['2/201/000.jpg', '2/201/001.jpg']);
    expect(pages.map((p) => p.bytes), [2, 3]);
    expect(await Directory(p.join(tmp.path, '2', '201')).exists(), isTrue);
    expect(await Directory(p.join(tmp.path, '1', '101')).exists(), isFalse);
  });

  test('transferChapter COPIES files, leaving the source in place', () async {
    await store.writePage(1, 101, 0, [1, 2], 'jpg');
    final pages = await store.transferChapter(1, 101, 2, 201, keepSource: true);
    expect(pages.single.relPath, '2/201/000.jpg');
    expect(await File(p.join(tmp.path, '1', '101', '000.jpg')).exists(), isTrue);
    expect(await File(p.join(tmp.path, '2', '201', '000.jpg')).exists(), isTrue);
  });

  test('transferChapter throws when the source has no files', () async {
    expect(
      () => store.transferChapter(1, 999, 2, 201, keepSource: false),
      throwsA(isA<OfflineTransferException>()),
    );
  });
}
