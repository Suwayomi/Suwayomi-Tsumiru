// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/source_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source/controller/source_controller.dart';

SourceDto _src({
  required String id,
  required String name,
  String lang = 'en',
  bool pinned = false,
  bool hidden = false,
}) =>
    SourceDto.fromJson({
      'displayName': name,
      'iconUrl': '',
      'id': id,
      'isConfigurable': false,
      'isNsfw': false,
      'lang': lang,
      'name': name,
      'supportsLatest': true,
      '__typename': 'SourceType',
      'meta': [
        if (pinned)
          {
            'key': 'webUI_isPinned',
            'value': 'true',
            '__typename': 'SourceMetaType',
          },
        if (hidden)
          {
            'key': 'tsumiru_isHidden',
            'value': 'true',
            '__typename': 'SourceMetaType',
          },
      ],
      'extension': {
        'pkgName': 'pkg',
        'repo': 'repo',
        '__typename': 'ExtensionType',
      },
    });

void main() {
  // Out of install order on purpose, to prove we sort.
  final mangaDex = _src(id: '1', name: 'MangaDex');
  final allManga = _src(id: '2', name: 'allmanga'); // lowercase -> case-insensitive
  final asura = _src(id: '3', name: 'Asura Scans', pinned: true);
  final bato = _src(id: '4', name: 'Bato', lang: 'ko');
  final sources = [mangaDex, allManga, asura, bato];

  group('isPinned', () {
    test('true only when webUI_isPinned meta == "true"', () {
      expect(asura.isPinned, isTrue);
      expect(mangaDex.isPinned, isFalse);
      // value "false" is not pinned
      expect(
        _src(id: '9', name: 'x').isPinned,
        isFalse,
      );
    });
  });

  group('isHidden', () {
    test('true only when tsumiru_isHidden meta == "true"', () {
      expect(_src(id: '9', name: 'x', hidden: true).isHidden, isTrue);
      expect(mangaDex.isHidden, isFalse);
      // a pinned-but-not-hidden source is not hidden
      expect(asura.isHidden, isFalse);
    });
  });

  group('groupAllSourcesByLanguage (Sources filter screen)', () {
    test('keeps pinned/hidden sources; shown before hidden, then by name', () {
      final hiddenSrc = _src(id: '5', name: 'Comick', hidden: true);
      final map = groupAllSourcesByLanguage([...sources, hiddenSrc]);
      // Asura is pinned but must still appear (unlike groupSourcesByLanguage);
      // hidden Comick sorts after the shown sources.
      expect(map['en']!.map((e) => e.name),
          ['allmanga', 'Asura Scans', 'MangaDex', 'Comick']);
      expect(map['ko']!.map((e) => e.name), ['Bato']);
    });
  });

  group('browsableSourceList (hidden sources dropped from browse)', () {
    test('removes hidden sources, keeps the rest', () {
      final hiddenSrc = _src(id: '5', name: 'Comick', hidden: true);
      final c = ProviderContainer(overrides: [
        visibleSourceListProvider
            .overrideWith((ref) => AsyncData([...sources, hiddenSrc])),
      ]);
      addTearDown(c.dispose);
      final out = c.read(browsableSourceListProvider).value!;
      expect(out.map((e) => e.name), isNot(contains('Comick')));
      expect(out.length, sources.length);
    });
  });

  group('pinnedSourcesFrom', () {
    test('returns only pinned sources, sorted by name', () {
      expect(pinnedSourcesFrom(sources).map((e) => e.name), ['Asura Scans']);
    });
  });

  group('groupSourcesByLanguage', () {
    test('sorts each language group alphabetically (case-insensitive)', () {
      final map = groupSourcesByLanguage(sources, null);
      expect(map['en']!.map((e) => e.name), ['allmanga', 'MangaDex']);
      expect(map['ko']!.map((e) => e.name), ['Bato']);
    });

    test('pinned sources are excluded from their language group', () {
      final map = groupSourcesByLanguage(sources, null);
      expect(map['en']!.any((e) => e.name == 'Asura Scans'), isFalse);
    });

    test('the last-used source is lifted into a "lastUsed" bucket', () {
      final map = groupSourcesByLanguage(sources, '1'); // MangaDex
      expect(map['lastUsed']!.single.name, 'MangaDex');
    });
  });

  group('sourceMapFilteredAndQueried (Sources tab name filter)', () {
    ProviderContainer containerWith(Map<String, List<SourceDto>> map) {
      final c = ProviderContainer(overrides: [
        sourceMapFilteredProvider.overrideWith((ref) => AsyncData(map)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('a blank query passes the grouped map through unchanged', () {
      final c = containerWith({
        'en': [mangaDex, allManga],
        'ko': [bato],
      });
      final out = c.read(sourceMapFilteredAndQueriedProvider).value!;
      expect(out['en']!.map((e) => e.name), ['MangaDex', 'allmanga']);
      expect(out['ko']!.map((e) => e.name), ['Bato']);
    });

    test('a query filters each group by source name, keeping grouping', () {
      final c = containerWith({
        'en': [mangaDex, allManga],
        'ko': [bato],
      });
      c.read(sourceSearchQueryProvider.notifier).update('dex');
      final out = c.read(sourceMapFilteredAndQueriedProvider).value!;
      expect(out['en']!.map((e) => e.name), ['MangaDex']);
      expect(out['ko'], isEmpty);
    });
  });
}
