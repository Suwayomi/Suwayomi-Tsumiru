import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_autocomplete.dart';
import 'package:tsumiru/src/features/quick_open/presentation/unified_search/unified_search_facets.dart';

const _facets = LibraryFacets(
  source: ['Comick', 'MangaDex'],
  status: ['completed', 'ongoing'],
  genre: ['Action', 'Slice of Life'],
  tag: [],
  author: [],
  artist: [],
);

void main() {
  test('value completion adds a trailing space and preserves negation', () {
    final t = activeTokenAt('source:man', 10);
    final s = suggestFor(t, _facets).single;
    final r = applySuggestion('source:man', t, s);
    expect(r.text, 'source:MangaDex ');
    expect(r.caret, 16);

    final negated = activeTokenAt('-source:man', 11);
    final negatedSuggestion = suggestFor(negated, _facets).single;
    final negatedResult = applySuggestion(
      '-source:man',
      negated,
      negatedSuggestion,
    );
    expect(negatedResult.text, '-source:MangaDex ');
  });
}
