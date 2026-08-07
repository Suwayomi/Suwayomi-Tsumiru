// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/migration/domain/chapter_matcher.dart';

ChapterState cs(int id, double number, {String name = ''}) => ChapterState(
      id: id,
      chapterNumber: number,
      name: name.isEmpty ? 'Chapter $number' : name,
      isRead: false,
      isBookmarked: false,
      lastPageRead: 0,
    );

void main() {
  test('pairs source ids to target ids by chapter number', () {
    final pairs = matchChaptersByNumber(
      source: [cs(101, 1), cs(102, 2), cs(103, 3)],
      target: [cs(201, 1), cs(202, 2), cs(203, 3)],
    );
    expect(pairs, [
      (fromId: 101, toId: 201),
      (fromId: 102, toId: 202),
      (fromId: 103, toId: 203),
    ]);
  });

  test('numbers match within float tolerance only', () {
    final pairs = matchChaptersByNumber(
      source: [cs(101, 1.0)],
      target: [cs(201, 1.005), cs(202, 1.5)],
    );
    expect(pairs, [(fromId: 101, toId: 201)]);
  });

  test('a source chapter with no numeric match is dropped', () {
    final pairs = matchChaptersByNumber(
      source: [cs(101, 1), cs(102, 99)],
      target: [cs(201, 1)],
    );
    expect(pairs, [(fromId: 101, toId: 201)]);
  });

  test('oneshots (negative number) match by exact lowercased name', () {
    final pairs = matchChaptersByNumber(
      source: [cs(101, -1, name: 'Oneshot')],
      target: [cs(201, -1, name: 'oneshot'), cs(202, -1, name: 'Extra')],
    );
    expect(pairs, [(fromId: 101, toId: 201)]);
  });

  test('each target is claimed at most once', () {
    // Two source chapters share a number; only the first claims the target.
    final pairs = matchChaptersByNumber(
      source: [cs(101, 5), cs(102, 5)],
      target: [cs(201, 5)],
    );
    expect(pairs, [(fromId: 101, toId: 201)]);
  });
}
