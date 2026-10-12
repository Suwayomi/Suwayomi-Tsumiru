// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/utils/crash/diagnostics.dart';

void main() {
  late List<String> lines;
  late ProviderContainer container;
  setUp(() {
    lines = [];
    setDiagnosticSink(lines.add);
    container = ProviderContainer();
  });
  tearDown(() {
    container.dispose();
    setDiagnosticSink(null);
  });

  test('each flip is logged once, with its reason', () {
    final notifier = container.read(serverUnreachableProvider.notifier);
    notifier.set(true, reason: 'op=GetCategoryMangas error=SocketException');
    notifier.set(true, reason: 'op=Other');
    notifier.set(false, reason: 'op=GetAbout');

    expect(lines, hasLength(2));
    expect(
      lines[0],
      contains(
        'reachability: unreachable '
        'op=GetCategoryMangas error=SocketException',
      ),
    );
    expect(lines[1], contains('reachability: reachable op=GetAbout'));
  });
}
