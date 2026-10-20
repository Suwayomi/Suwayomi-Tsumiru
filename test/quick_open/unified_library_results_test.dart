import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_providers.dart';

void main() {
  test('caps at kUnifiedSectionLimit while counting every match', () {
    final many = List.generate(20, (i) => 'Manga $i');
    expect(countLibraryTitles(many, 'manga', (s, q) => true), 20);
    final hits = matchLibraryTitles(many, 'manga', (s, q) => true);
    expect(hits.length, kUnifiedSectionLimit);
  });

  test('detects operator queries, including mid-string and {a|b} groups', () {
    expect(queryUsesOperator('source:mangadex'), isTrue);
    expect(queryUsesOperator('tag:isekai'), isTrue);
    expect(queryUsesOperator('status:completed'), isTrue);
    // operator mid-string, after a plain word
    expect(queryUsesOperator('solo unread:true'), isTrue);
    // case-insensitive key
    expect(queryUsesOperator('Source:mangadex'), isTrue);
    expect(queryUsesOperator('{genre:action|genre:romance}'), isTrue);
    // an unknown key is NOT an operator (titles like Re:Zero search plainly)
    expect(queryUsesOperator('Re:Zero'), isFalse);
    expect(queryUsesOperator('chapter:1 club'), isFalse);
  });
}
