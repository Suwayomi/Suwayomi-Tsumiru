// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_endpoint.dart';
import 'package:tsumiru/src/utils/crash/diagnostics.dart';

const _lan = 'http://192.168.5.5:4567';
const _external = 'https://suwayomi.example.net';

void main() {
  final lines = <String>[];
  setUp(() {
    lines.clear();
    setDiagnosticSink(lines.add);
  });
  tearDown(() => setDiagnosticSink(null));

  group('pickBackgroundServerBase', () {
    Future<String> pick({required String active, required bool lanUp}) =>
        pickBackgroundServerBase(
          active: active,
          lanUrl: _lan,
          externalUrl: _external,
          source: 'test',
          isReachable: (url) async {
            expect(url, _lan, reason: 'only the LAN address is probed');
            return lanUp;
          },
        );

    test(
      'left home after the app last ran on the LAN: the external address',
      () async {
        expect(await pick(active: _lan, lanUp: false), _external);
        expect(
          lines.single,
          contains('selected=external differs-from-foreground'),
        );
      },
    );
  });
}
