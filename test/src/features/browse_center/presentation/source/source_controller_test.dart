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
}) => SourceDto.fromJson({
  'displayName': name,
  'iconUrl': '',
  'id': id,
  'isConfigurable': false,
  'contentWarning': 'SAFE',
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
    'isObsolete': false,
    '__typename': 'ExtensionType',
  },
});

void main() {
  final mangaDex = _src(id: '1', name: 'MangaDex');
  final asura = _src(id: '3', name: 'Asura Scans', pinned: true);
  final sources = [mangaDex, asura];

  test('pinned and hidden meta parse only when the value is "true"', () {
    expect(asura.isPinned, isTrue);
    expect(mangaDex.isPinned, isFalse);
    expect(_src(id: '9', name: 'x').isPinned, isFalse);

    expect(_src(id: '9', name: 'x', hidden: true).isHidden, isTrue);
    expect(mangaDex.isHidden, isFalse);
    // a pinned-but-not-hidden source is not hidden
    expect(asura.isHidden, isFalse);
  });

  group('browsableSourceList (hidden sources dropped from browse)', () {
    test('removes hidden sources, keeps the rest', () {
      final hiddenSrc = _src(id: '5', name: 'Comick', hidden: true);
      final c = ProviderContainer(
        overrides: [
          visibleSourceListProvider.overrideWith(
            (ref) => AsyncData([...sources, hiddenSrc]),
          ),
        ],
      );
      addTearDown(c.dispose);
      final out = c.read(browsableSourceListProvider).value!;
      expect(out.map((e) => e.name), isNot(contains('Comick')));
      expect(out.length, sources.length);
    });
  });
}
