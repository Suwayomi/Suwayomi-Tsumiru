// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/offline/data/background/background_endpoint.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/background/background_work_order.dart';
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

    test('back home after the app last ran away: the LAN address', () async {
      expect(await pick(active: _external, lanUp: true), _lan);
      expect(lines.single, contains('selected=lan differs-from-foreground'));
    });

    test(
      'same network as the foreground: its address, logged as such',
      () async {
        expect(await pick(active: _lan, lanUp: true), _lan);
        expect(await pick(active: _external, lanUp: false), _external);
        expect(lines, everyElement(isNot(contains('differs'))));
      },
    );

    test(
      'without both addresses, the foreground address and no probe',
      () async {
        for (final (lan, external) in [
          (null, _external),
          (_lan, null),
          ('', _external),
        ]) {
          expect(
            await pickBackgroundServerBase(
              active: _lan,
              lanUrl: lan,
              externalUrl: external,
              source: 'test',
              isReachable: (_) async => fail('must not probe'),
            ),
            _lan,
          );
        }
        expect(lines, isEmpty);
      },
    );
  });

  group('NotificationEndpoint', () {
    const configured = NotificationEndpoint(
      baseUrl: _lan,
      port: 4567,
      addPort: false,
      lanUrl: _lan,
      externalUrl: _external,
    );

    test('keeps both addresses through the persisted config', () {
      final read = NotificationEndpoint.fromJson(
        jsonDecode(jsonEncode(configured.toJson())) as Map<String, Object?>,
      );
      expect(read.lanUrl, _lan);
      expect(read.externalUrl, _external);
    });

    test(
      'a config from before they were kept still reads, with no alternate',
      () async {
        final legacy = NotificationEndpoint.fromJson({
          'baseUrl': _lan,
          'port': null,
          'addPort': false,
        });
        expect(legacy.lanUrl, isNull);
        final resolved = await legacy.forThisNetwork(
          source: 'test',
          isReachable: (_) async => fail('must not probe'),
        );
        expect(resolved.baseUrl, _lan);
      },
    );

    test('a run away from home reaches the same server at its external '
        'address, with the same port rules', () async {
      final resolved = await configured.forThisNetwork(
        source: 'test',
        isReachable: (_) async => false,
      );
      expect(resolved.baseUrl, _external);
      expect(resolved.port, 4567);
      expect(resolved.addPort, isFalse);
      // The verified address the identity checks rely on stays in the config.
      expect(configured.baseUrl, _lan);
    });
  });

  test('a work order keeps both addresses, and an older one still reads', () {
    final order = BackgroundWorkOrder(
      chapterIds: const [1],
      mangaIdByChapter: const {1: 2},
      serverBase: _lan,
      lanUrl: _lan,
      externalUrl: _external,
      port: null,
      addPort: false,
      wifiOnly: false,
      auth: const BackgroundTokenRecord(gen: 0, authType: 'none'),
      baseDir: '/tmp',
    );
    final json = jsonDecode(jsonEncode(order.toJson())) as Map<String, Object?>;
    final read = BackgroundWorkOrder.fromJson(json);
    expect(read.lanUrl, _lan);
    expect(read.externalUrl, _external);

    final legacy = BackgroundWorkOrder.fromJson(
      json
        ..remove('lanUrl')
        ..remove('externalUrl'),
    );
    expect(legacy.lanUrl, isNull);
    expect(legacy.externalUrl, isNull);
    expect(legacy.serverBase, _lan);
  });
}
