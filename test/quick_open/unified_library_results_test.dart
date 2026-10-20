import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_providers.dart';

void main() {
  test('caps at kUnifiedSectionLimit', () {
    final many = List.generate(20, (i) => 'Manga $i');
    final hits = matchLibraryTitles(many, 'manga', (s, q) => true);
    expect(hits.length, kUnifiedSectionLimit);
  });

  group('countLibraryTitles', () {
    test('counts every match without the cap', () {
      final many = List.generate(20, (i) => 'Manga $i');
      expect(countLibraryTitles(many, 'manga', (s, q) => true), 20);
      expect(
        matchLibraryTitles(many, 'manga', (s, q) => true).length,
        kUnifiedSectionLimit,
      );
    });
  });

  group('queryUsesOperator', () {
    test('a recognized metatag key makes it an operator query', () {
      expect(queryUsesOperator('source:mangadex'), isTrue);
      expect(queryUsesOperator('tag:isekai'), isTrue);
      expect(queryUsesOperator('status:completed'), isTrue);
      // operator mid-string, after a plain word
      expect(queryUsesOperator('solo unread:true'), isTrue);
      // case-insensitive key
      expect(queryUsesOperator('Source:mangadex'), isTrue);
    });

    test(
      'an unknown key is NOT an operator (titles like Re:Zero search plainly)',
      () {
        expect(queryUsesOperator('Re:Zero'), isFalse);
        expect(queryUsesOperator('chapter:1 club'), isFalse);
      },
    );

    test(
      'a {a|b} group counts as an operator (parity with the library bar)',
      () {
        expect(queryUsesOperator('{genre:action|genre:romance}'), isTrue);
      },
    );
  });

  group('plainQueryText', () {
    test('plain words survive; operator tokens are stripped', () {
      expect(plainQueryText('bad'), 'bad');
      expect(plainQueryText('chainsaw source:mangadex'), 'chainsaw');
      expect(plainQueryText('the player, unread:true'), 'the player');
    });

    test(
      'quoted multi-word values stay whole and are not leaked as fragments',
      () {
        // Regression: a naive space-split leaked `of life"` to source search.
        expect(plainQueryText('tag:"slice of life"'), '');
        expect(plainQueryText('author:"Kubo Tite" bleach'), 'bleach');
      },
    );
  });
}
