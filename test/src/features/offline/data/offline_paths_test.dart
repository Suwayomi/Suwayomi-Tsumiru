// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';

void main() {
  // Base dir is injected so the path logic is testable without path_provider /
  // a real device. Production resolves the base at runtime; only RELATIVE paths
  // are ever persisted (iOS rewrites the absolute container path across installs).
  const base = '/app-support/offline';
  const paths = OfflinePaths(base);

  group('relative path generation', () {
    test('pageRel is <mangaId>/<chapterId>/<NNN>.<ext>, zero-padded to 3', () {
      expect(paths.pageRel(117, 2000, 0, 'jpg'), '117/2000/000.jpg');
      expect(paths.pageRel(117, 2000, 5, 'png'), '117/2000/005.png');
      expect(paths.pageRel(1, 1, 123, 'webp'), '1/1/123.webp');
    });
  });

  group('absolute() resolves a relative path against the base', () {});
}
