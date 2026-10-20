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
}
