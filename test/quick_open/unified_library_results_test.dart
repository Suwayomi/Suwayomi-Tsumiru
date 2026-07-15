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
}
