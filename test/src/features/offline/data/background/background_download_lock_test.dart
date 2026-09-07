// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_lock.dart';

void main() {
  late Directory tmp;
  late File anchor;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('tsumiru-lock-');
    anchor = File('${tmp.path}/.bg_lock');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a held lock refuses a second holder until release', () async {
    final a = BackgroundDownloadLock(anchor);
    final b = BackgroundDownloadLock(anchor);
    addTearDown(a.release);
    addTearDown(b.release);
    expect(await a.acquire('fgs'), isTrue);
    expect(await b.acquire('wm-catchup'), isFalse);
    await a.release();
    expect(await b.acquire('wm-catchup'), isTrue);
  });

  test('a holder excludes another isolate until release', () async {
    final holder = BackgroundDownloadLock(anchor);
    addTearDown(holder.release);
    expect(await holder.acquire('fgs'), isTrue);
    final path = anchor.path;
    Future<bool> contend() => Isolate.run(() async {
      final contender = BackgroundDownloadLock(File(path));
      try {
        return await contender.acquire('isolate');
      } finally {
        await contender.release();
      }
    });
    expect(await contend(), isFalse);
    await holder.release();
    expect(await contend(), isTrue);
  });

  test('a stale marker cannot steal active SQLite ownership', () async {
    final owner = sqlite3.open('${anchor.path}.sqlite');
    owner.execute('BEGIN IMMEDIATE');
    addTearDown(owner.close);
    anchor.writeAsStringSync('fgs#999');
    anchor.setLastModifiedSync(
      DateTime.now().subtract(const Duration(minutes: 5)),
    );
    final claimant = BackgroundDownloadLock(anchor);
    addTearDown(claimant.release);
    expect(await claimant.acquire('wm-catchup'), isFalse);
    owner.execute('ROLLBACK');
    expect(await claimant.acquire('wm-catchup'), isTrue);
  });

  test('a yield request survives contention and release', () async {
    final holder = BackgroundDownloadLock(anchor);
    final replay = BackgroundDownloadLock(anchor);
    addTearDown(holder.release);
    addTearDown(replay.release);
    expect(await holder.acquire('fgs'), isTrue);
    expect(await holder.yieldRequested(), isFalse);
    await replay.requestYield();
    expect(await replay.acquire('replay'), isFalse);
    expect(await holder.yieldRequested(), isTrue);
    await holder.release();
    expect(await replay.yieldRequested(), isTrue);
    expect(await replay.acquire('replay'), isTrue);
    expect(await replay.yieldRequested(), isFalse);
  });
}
