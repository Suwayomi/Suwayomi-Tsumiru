import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_providers.dart';

void main() {
  test('blank query yields no matches', () {
    expect(matchLibraryTitles(const ['A', 'B'], '', (s, q) => true), isEmpty);
  });

  test('caps at kUnifiedSectionLimit', () {
    final many = List.generate(20, (i) => 'Manga $i');
    final hits = matchLibraryTitles(many, 'manga', (s, q) => true);
    expect(hits.length, kUnifiedSectionLimit);
  });

  test('filters by the provided predicate', () {
    final hits =
        matchLibraryTitles(const ['Naruto', 'Bleach'], 'nar', (s, q) => s == 'Naruto');
    expect(hits, ['Naruto']);
  });

  group('titleMatchesQuery', () {
    test('matches only the title, not other metadata', () {
      // The reported bug: "bad" surfaced titles that only mention it in their
      // description/author. Title-only matching must reject those.
      expect(titleMatchesQuery('The Player Hides His Past', 'bad'), isFalse);
      expect(titleMatchesQuery('Bad Born Blood', 'bad'), isTrue);
    });

    test('is case-insensitive and trims the query', () {
      expect(titleMatchesQuery('Bad Born Blood', '  BAD '), isTrue);
    });
  });

  group('queryUsesOperator', () {
    test('plain words are not operators', () {
      expect(queryUsesOperator('bad'), isFalse);
      expect(queryUsesOperator('solo leveling'), isFalse);
      expect(queryUsesOperator(''), isFalse);
    });

    test('a recognized metatag key makes it an operator query', () {
      expect(queryUsesOperator('source:mangadex'), isTrue);
      expect(queryUsesOperator('tag:isekai'), isTrue);
      expect(queryUsesOperator('status:completed'), isTrue);
      // operator mid-string, after a plain word
      expect(queryUsesOperator('solo unread:true'), isTrue);
      // case-insensitive key
      expect(queryUsesOperator('Source:mangadex'), isTrue);
    });

    test('an unknown key is NOT an operator (titles like Re:Zero search plainly)',
        () {
      expect(queryUsesOperator('Re:Zero'), isFalse);
      expect(queryUsesOperator('chapter:1 club'), isFalse);
    });
  });

  group('plainQueryText', () {
    test('a pure operator query has no plain text (nothing to search sources for)',
        () {
      expect(plainQueryText('unread:true'), '');
      expect(plainQueryText('source:x unread:true'), '');
      expect(plainQueryText('-status:completed'), '');
    });

    test('plain words survive; operator tokens are stripped', () {
      expect(plainQueryText('bad'), 'bad');
      expect(plainQueryText('chainsaw source:mangadex'), 'chainsaw');
      expect(plainQueryText('the player, unread:true'), 'the player');
    });
  });
}
