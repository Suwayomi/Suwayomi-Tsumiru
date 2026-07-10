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
}) =>
    LibraryFilterFields(
      title: title,
      author: author,
      artist: artist,
      genres: genres,
      unreadCount: unreadCount,
      downloadCount: downloadCount,
      rating: rating,
      userTags: userTags,
    );

bool _matches(String query, LibraryFilterFields f) =>
    LibrarySearchQuery.parse(query).matches(f);

void main() {
  group('empty / plain text', () {
    test('empty query matches everything', () {
      expect(LibrarySearchQuery.parse('').isEmpty, isTrue);
      expect(LibrarySearchQuery.parse('   ').isEmpty, isTrue);
      expect(_matches('', _manga()), isTrue);
    });

    test('bare word matches title, author, genre, or custom tag', () {
      expect(_matches('piece', _manga()), isTrue); // title
      expect(_matches('oda', _manga()), isTrue); // author
      expect(_matches('adventure', _manga()), isTrue); // source genre
      expect(_matches('rere', _manga(userTags: ['Reread'])), isTrue); // custom
      expect(_matches('naruto', _manga()), isFalse);
    });

    test('multiple bare words are AND-ed', () {
      expect(_matches('one action', _manga()), isTrue);
      expect(_matches('one horror', _manga()), isFalse);
    });

    test('comma separates terms just like a space', () {
      expect(_matches('one,action', _manga()), isTrue);
      expect(_matches('one,horror', _manga()), isFalse);
    });
  });

  group('tag: (exact, case-insensitive)', () {
    final m = _manga(userTags: ['Reread', 'Favorites']);
    test('exact match hits regardless of case', () {
      expect(_matches('tag:reread', m), isTrue);
      expect(_matches('tag:REREAD', m), isTrue);
    });
    test('is NOT substring — a prefix must not match', () {
      expect(_matches('tag:rere', m), isFalse);
      expect(_matches('tag:favorite', m), isFalse);
    });
    test('quoted multi-word tag value', () {
      final t = _manga(userTags: ['slice of life']);
      expect(_matches('tag:"slice of life"', t), isTrue);
      expect(_matches('tag:slice', t), isFalse);
    });
    test('tag: also matches a source genre exactly', () {
      // Every manga has source genres; tag: filters those too, not just custom.
      expect(_matches('tag:action', _manga()), isTrue); // genre "Action"
      expect(_matches('tag:seinen', _manga(genres: ['Seinen'])), isTrue);
      expect(_matches('tag:act', _manga()), isFalse); // exact, not substring
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
    test('bare number is exact', () {
      expect(_matches('rating:4', _manga(rating: 4)), isTrue);
      expect(_matches('rating:4', _manga(rating: 3)), isFalse);
    });
    test('comparison operators', () {
      expect(_matches('rating:>=4', _manga(rating: 5)), isTrue);
      expect(_matches('rating:>=4', _manga(rating: 3)), isFalse);
      expect(_matches('rating:<2', _manga(rating: 1)), isTrue);
      expect(_matches('rating:>3', _manga(rating: 3)), isFalse);
    });
    test('unrated counts as 0', () {
      expect(_matches('rating:0', _manga(rating: null)), isTrue);
      expect(_matches('rating:>=1', _manga(rating: null)), isFalse);
    });
  });

  group('boolean metatags', () {
    test('unread', () {
      expect(_matches('unread:true', _manga(unreadCount: 3)), isTrue);
      expect(_matches('unread:false', _manga(unreadCount: 3)), isFalse);
      expect(_matches('unread:false', _manga(unreadCount: 0)), isTrue);
    });
    test('downloaded', () {
      expect(_matches('downloaded:true', _manga(downloadCount: 2)), isTrue);
      expect(_matches('downloaded:true', _manga(downloadCount: 0)), isFalse);
    });
  });

  group('negation', () {
    test('-tag: excludes', () {
      final m = _manga(userTags: ['Dropped']);
      expect(_matches('-tag:dropped', m), isFalse);
      expect(_matches('-tag:dropped', _manga(userTags: ['Reread'])), isTrue);
    });
    test('-word excludes on any text field', () {
      expect(_matches('-naruto', _manga()), isTrue);
      expect(_matches('-oda', _manga()), isFalse);
    });
  });

  group('robustness', () {
    test('unrecognized key falls back to plain text (Re:Zero)', () {
      final m = _manga(title: 'Re:Zero');
      expect(_matches('re:zero', m), isTrue);
    });
    test('half-typed metatag key is ignored (matches all)', () {
      expect(_matches('tag:', _manga()), isTrue);
    });
    test('negated half-typed metatag stays a no-op (must not hide all)', () {
      // While typing `-unread:true`, the intermediate `-unread:t` must not
      // blank the library.
      expect(_matches('-unread:t', _manga()), isTrue);
      expect(_matches('-rating:>', _manga(rating: 4)), isTrue);
    });
    test('overflowing rating number does not throw and is a no-op', () {
      expect(
          () => _matches('rating:99999999999999999999999999', _manga()),
          returnsNormally);
      expect(_matches('rating:99999999999999999999999999', _manga()), isTrue);
    });
    test('combined query: tag AND rating AND bare word', () {
      final m = _manga(userTags: ['Reread'], rating: 5);
      expect(_matches('tag:reread rating:>=4 piece', m), isTrue);
      expect(_matches('tag:reread rating:>=4 naruto', m), isFalse);
    });
  });
}
