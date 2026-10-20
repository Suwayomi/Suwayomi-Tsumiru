// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/library_search_query.dart';

LibraryFilterFields _manga({
  String title = 'One Piece',
  String? author = 'Eiichiro Oda',
  String? artist = 'Eiichiro Oda',
  List<String> genres = const ['Action', 'Adventure', 'Slice of Life'],
  int unreadCount = 3,
  int downloadCount = 0,
  int? rating,
  List<String> userTags = const [],
  String? status = 'ONGOING',
  String? sourceName = 'MangaDex',
  Set<String> trackers = const {},
}) => LibraryFilterFields(
  title: title,
  author: author,
  artist: artist,
  genres: genres,
  unreadCount: unreadCount,
  downloadCount: downloadCount,
  rating: rating,
  userTags: userTags,
  status: status,
  sourceName: sourceName,
  trackers: trackers,
);

bool _matches(String query, LibraryFilterFields f) =>
    LibrarySearchQuery.parse(query).matches(f);

void main() {
  group('empty / plain text', () {
    test('multiple bare words are AND-ed', () {
      expect(_matches('one action', _manga()), isTrue);
      expect(_matches('one horror', _manga()), isFalse);
    });
  });

  group('tag: (exact, case-insensitive)', () {
    final m = _manga(userTags: ['Reread', 'Favorites']);
    test('exact match hits regardless of case', () {
      expect(_matches('tag:reread', m), isTrue);
      expect(_matches('tag:REREAD', m), isTrue);
    });
    test('quoted multi-word tag value', () {
      final t = _manga(userTags: ['slice of life']);
      expect(_matches('tag:"slice of life"', t), isTrue);
      expect(_matches('tag:slice', t), isFalse);
    });
  });

  group('genre: (substring, case-insensitive)', () {
    test('substring matches', () {
      expect(_matches('genre:life', _manga()), isTrue); // Slice of Life
      expect(_matches('genre:ACTION', _manga()), isTrue);
      expect(_matches('genre:horror', _manga()), isFalse);
    });
  });

  group('text field metatags', () {
    test('author / artist / title substring', () {
      expect(_matches('author:oda', _manga()), isTrue);
      expect(_matches('artist:eiichiro', _manga()), isTrue);
      expect(_matches('title:piece', _manga()), isTrue);
      expect(_matches('author:kishimoto', _manga()), isFalse);
    });
  });

  group('rating:', () {
    test('comparison operators', () {
      expect(_matches('rating:>=4', _manga(rating: 5)), isTrue);
      expect(_matches('rating:>=4', _manga(rating: 3)), isFalse);
      expect(_matches('rating:<2', _manga(rating: 1)), isTrue);
      expect(_matches('rating:>3', _manga(rating: 3)), isFalse);
    });
  });

  group('boolean metatags', () {
    test('unread', () {
      expect(_matches('unread:true', _manga(unreadCount: 3)), isTrue);
      expect(_matches('unread:false', _manga(unreadCount: 3)), isFalse);
      expect(_matches('unread:false', _manga(unreadCount: 0)), isTrue);
    });
  });

  group('negation', () {
    test('-tag: excludes', () {
      final m = _manga(userTags: ['Dropped']);
      expect(_matches('-tag:dropped', m), isFalse);
      expect(_matches('-tag:dropped', _manga(userTags: ['Reread'])), isTrue);
    });
  });

  group('robustness', () {
    test('unrecognized key falls back to plain text (Re:Zero)', () {
      final m = _manga(title: 'Re:Zero');
      expect(_matches('re:zero', m), isTrue);
    });
  });

  group('status:', () {
    test('exact enum name matches', () {
      expect(_matches('status:ongoing', _manga(status: 'ONGOING')), isTrue);
      expect(_matches('status:completed', _manga(status: 'ONGOING')), isFalse);
    });
  });

  group('source:', () {
    test('substring match on source name, case-insensitive', () {
      expect(
        _matches('source:mangadex', _manga(sourceName: 'MangaDex')),
        isTrue,
      );
      expect(_matches('source:dex', _manga(sourceName: 'MangaDex')), isTrue);
      expect(
        _matches('source:comick', _manga(sourceName: 'MangaDex')),
        isFalse,
      );
    });
  });

  group('tracked:', () {
    test('bool form checks for any tracker', () {
      expect(_matches('tracked:true', _manga(trackers: {'anilist'})), isTrue);
      expect(_matches('tracked:true', _manga(trackers: {})), isFalse);
      expect(_matches('tracked:false', _manga(trackers: {})), isTrue);
    });
  });

  group('{a|b} OR groups', () {});
}
