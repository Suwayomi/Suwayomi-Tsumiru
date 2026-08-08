// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  test('a held lock refuses a second holder', () async {
    final a = BackgroundDownloadLock(anchor);
    final b = BackgroundDownloadLock(anchor);
    expect(await a.acquire('fgs'), isTrue);
    expect(await b.acquire('wm-catchup'), isFalse);
    await a.release();
    expect(await b.acquire('wm-catchup'), isTrue);
    await b.release();
  });

  test('a yield request survives heartbeats and reaches the holder', () async {
    final holder = BackgroundDownloadLock(anchor);
    final replay = BackgroundDownloadLock(anchor);
    expect(await holder.acquire('fgs'), isTrue);
    expect(await holder.yieldRequested(), isFalse);

    await replay.requestYield();
    expect(await holder.yieldRequested(), isTrue,
        reason: 'the flag is a marker file — no renewal can clobber it');
    await holder.release();
  });

  test('a displaced holder cannot delete its successor\'s lock', () async {
    final a = BackgroundDownloadLock(anchor);
    expect(await a.acquire('fgs'), isTrue);
    // Simulate a steal: the successor rewrites the holder identity.
    a.lockFile.writeAsStringSync('replay#123');

    await a.release();
    expect(a.lockFile.existsSync(), isTrue,
        reason: 'release is owner-only — the stolen lock must survive');
  });

  test('a stale lock is broken and re-acquired', () async {
    // A dead holder: lock file present, heartbeat long past staleness.
    anchor.parent.createSync(recursive: true);
    anchor.writeAsStringSync('fgs#999');
    anchor.setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 5)));

    final claimant = BackgroundDownloadLock(anchor);
    expect(await claimant.acquire('wm-catchup'), isTrue,
        reason: 'heartbeat age past staleAfter means the holder is dead');
    await claimant.release();
    expect(anchor.existsSync(), isFalse);
  });
}
