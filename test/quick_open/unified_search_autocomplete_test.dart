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

List<String> _displays(List<SearchSuggestion> s) =>
    s.map((e) => e.display).toList();

void main() {
  group('activeTokenAt', () {
    test('token at end of string', () {
      final t = activeTokenAt('source:man', 10);
      expect(t.raw, 'source:man');
      expect(t.hasColon, isTrue);
      expect(t.key, 'source');
      expect(t.partialValue, 'man');
    });
  });

  group('suggestFor — key mode', () {
    test('prefix suggests matching operator keys', () {
      final s = suggestFor(activeTokenAt('sou', 3), _facets);
      expect(_displays(s), contains('source:'));
    });
  });

  group('suggestFor — value mode', () {
    test('source values come from the library, filtered by what is typed', () {
      final s = suggestFor(activeTokenAt('source:man', 10), _facets);
      expect(_displays(s), ['source:MangaDex']);
      expect(s.single.insertText, 'source:MangaDex');
      expect(s.single.isKey, isFalse);
    });

    test('boolean operators suggest true/false', () {
      expect(_displays(suggestFor(activeTokenAt('unread:', 7), _facets)), [
        'unread:true',
        'unread:false',
      ]);
      expect(_displays(suggestFor(activeTokenAt('unread:t', 8), _facets)), [
        'unread:true',
      ]);
    });
  });

  group('applySuggestion', () {
    test('key completion inserts key: and leaves caret after the colon', () {
      final t = activeTokenAt('sou', 3);
      final s = suggestFor(
        t,
        _facets,
      ).firstWhere((e) => e.display == 'source:');
      final r = applySuggestion('sou', t, s);
      expect(r.text, 'source:');
      expect(r.caret, 7);
    });

    test('value completion adds a trailing space for the next term', () {
      final t = activeTokenAt('source:man', 10);
      final s = suggestFor(t, _facets).single;
      final r = applySuggestion('source:man', t, s);
      expect(r.text, 'source:MangaDex ');
      expect(r.caret, 16);
    });

    test('negation prefix is preserved on completion', () {
      final t = activeTokenAt('-source:man', 11);
      final s = suggestFor(t, _facets).single;
      final r = applySuggestion('-source:man', t, s);
      expect(r.text, '-source:MangaDex ');
    });
  });
}
