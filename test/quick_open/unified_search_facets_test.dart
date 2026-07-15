import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/library_search_query.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_facets.dart';

void main() {
  test('empty library yields empty facets', () {
    final f = buildLibraryFacets(const []);
    expect(f.source, isEmpty);
    expect(f.valuesFor('source'), isEmpty);
    // Free-form / boolean operators have no enumerable facet.
    expect(f.valuesFor('rating'), isNull);
    expect(f.valuesFor('unread'), isNull);
  });

  test('collects distinct, sorted values per field', () {
    final fields = [
      const LibraryFilterFields(
        title: 'A',
        sourceName: 'MangaDex',
        genres: ['Action', 'Romance'],
        status: 'ONGOING',
        userTags: ['fav'],
        author: 'Kubo',
      ),
      const LibraryFilterFields(
        title: 'B',
        sourceName: 'Comick',
        genres: ['Action'],
        status: 'COMPLETED',
        userTags: ['fav', 'dark'],
        author: 'Kubo',
      ),
    ];
    final f = buildLibraryFacets(fields);
    expect(f.source, ['Comick', 'MangaDex']); // sorted
    expect(f.genre, ['Action', 'Romance']); // distinct + sorted
    expect(f.status, ['completed', 'ongoing']); // lowercased for display + sorted
    expect(f.tag, ['dark', 'fav']);
    expect(f.author, ['Kubo']); // distinct
    expect(f.valuesFor('genre'), ['Action', 'Romance']);
  });

  test('skips null/empty field values', () {
    final f = buildLibraryFacets(const [
      LibraryFilterFields(title: 'A', sourceName: '', status: null, author: ''),
    ]);
    expect(f.source, isEmpty);
    expect(f.status, isEmpty);
    expect(f.author, isEmpty);
  });
}
