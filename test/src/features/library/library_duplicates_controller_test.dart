// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/library/presentation/duplicates/controller/library_duplicates_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';

import '../manga_book/reader/reader_test_fixtures.dart';

MangaDto _m(int id, String title, {String? description}) =>
    testManga().copyWith.call(id: id, title: title, description: description);

ProviderContainer _container({
  required FutureOr<List<MangaDto>?> Function(Ref ref) library,
}) {
  final c = ProviderContainer(
    overrides: [libraryMangaListProvider.overrideWith(library)],
  );
  return c;
}

void main() {
  test('a fake library with a title duplicate produces one group', () async {
    final c = _container(
      library: (ref) async => [_m(1, 'Solo Leveling'), _m(2, 'Solo Leveling')],
    );
    addTearDown(c.dispose);

    final groups = await c.read(
      libraryDuplicatesProvider(checkDescriptions: false).future,
    );

    expect(groups, hasLength(1));
    expect(groups.single.memberIds, [1, 2]);
  });

  test('an empty library produces no groups', () async {
    final c = _container(library: (ref) async => const []);
    addTearDown(c.dispose);

    final groups = await c.read(
      libraryDuplicatesProvider(checkDescriptions: false).future,
    );

    expect(groups, isEmpty);
  });

  test(
    'a null library (offline read failure) fails open to no groups',
    () async {
      final c = _container(library: (ref) async => null);
      addTearDown(c.dispose);

      final groups = await c.read(
        libraryDuplicatesProvider(checkDescriptions: false).future,
      );

      expect(groups, isEmpty);
    },
  );

  test('rescan refetches the library so removals show up', () async {
    // Simulates a removal happening elsewhere (e.g. the details page)
    // between scans.
    var libraryReads = 0;
    var removed = false;
    final c = _container(
      library: (ref) async {
        libraryReads++;
        return removed
            ? [_m(1, 'Solo Leveling')]
            : [_m(1, 'Solo Leveling'), _m(2, 'Solo Leveling')];
      },
    );
    addTearDown(c.dispose);

    final provider = libraryDuplicatesProvider(checkDescriptions: false);
    final sub = c.listen(provider, (_, _) {});
    addTearDown(sub.close);

    expect(await c.read(provider.future), hasLength(1));
    expect(libraryReads, 1);

    removed = true;
    await c.read(provider.notifier).rescan();
    expect(await c.read(provider.future), isEmpty);
    expect(libraryReads, 2);
  });
}
