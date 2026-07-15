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

List<String> _displays(List<SearchSuggestion> s) => s.map((e) => e.display).toList();

void main() {
  group('activeTokenAt', () {
    test('token at end of string', () {
      final t = activeTokenAt('source:man', 10);
      expect(t.raw, 'source:man');
      expect(t.hasColon, isTrue);
      expect(t.key, 'source');
      expect(t.partialValue, 'man');
    });

    test('bare key partial (no colon yet)', () {
      final t = activeTokenAt('sou', 3);
      expect(t.hasColon, isFalse);
      expect(t.keyPartial, 'sou');
    });

    test('only the token under the caret, not the whole line', () {
      // "foo source:m bar", caret right after the 'm'.
      const text = 'foo source:m bar';
      final t = activeTokenAt(text, 12);
      expect(t.raw, 'source:m');
      expect(t.key, 'source');
      expect(t.partialValue, 'm');
    });

    test('a leading - negation is stripped from key/value but noted', () {
      final t = activeTokenAt('-status:on', 10);
      expect(t.negated, isTrue);
      expect(t.key, 'status');
      expect(t.partialValue, 'on');
    });

    test('empty when caret sits on a blank boundary', () {
      expect(activeTokenAt('', 0).isEmpty, isTrue);
      expect(activeTokenAt('foo ', 4).isEmpty, isTrue);
    });
  });

  group('suggestFor — key mode', () {
    test('prefix suggests matching operator keys', () {
      final s = suggestFor(activeTokenAt('sou', 3), _facets);
      expect(_displays(s), contains('source:'));
    });

    test('one letter can match several keys', () {
      final s = suggestFor(activeTokenAt('s', 1), _facets);
      expect(_displays(s), containsAll(['source:', 'status:']));
    });

    test('a fully-typed key still offers the colon completion', () {
      final s = suggestFor(activeTokenAt('source', 6), _facets);
      expect(_displays(s), contains('source:'));
    });

    test('no key suggestions when the prefix matches nothing', () {
      expect(suggestFor(activeTokenAt('sol', 3), _facets), isEmpty);
    });
  });

  group('suggestFor — value mode', () {
    test('source values come from the library, filtered by what is typed', () {
      final s = suggestFor(activeTokenAt('source:man', 10), _facets);
      expect(_displays(s), ['source:MangaDex']);
      expect(s.single.insertText, 'source:MangaDex');
      expect(s.single.isKey, isFalse);
    });

    test('bare value shows the whole facet list', () {
      final s = suggestFor(activeTokenAt('status:', 7), _facets);
      expect(_displays(s), ['status:completed', 'status:ongoing']);
    });

    test('boolean operators suggest true/false', () {
      expect(_displays(suggestFor(activeTokenAt('unread:', 7), _facets)),
          ['unread:true', 'unread:false']);
      expect(_displays(suggestFor(activeTokenAt('unread:t', 8), _facets)),
          ['unread:true']);
    });

    test('rating is free-form — no value suggestions', () {
      expect(suggestFor(activeTokenAt('rating:>3', 9), _facets), isEmpty);
    });

    test('a fully-typed value is not echoed back as a suggestion', () {
      expect(suggestFor(activeTokenAt('unread:true', 11), _facets), isEmpty);
      expect(suggestFor(activeTokenAt('status:ongoing', 14), _facets), isEmpty);
    });

    test('multi-word values are quoted in the insert text', () {
      final s = suggestFor(activeTokenAt('genre:sli', 9), _facets);
      expect(s.single.display, 'genre:Slice of Life');
      expect(s.single.insertText, 'genre:"Slice of Life"');
    });
  });

  group('applySuggestion', () {
    test('key completion inserts key: and leaves caret after the colon', () {
      final t = activeTokenAt('sou', 3);
      final s = suggestFor(t, _facets).firstWhere((e) => e.display == 'source:');
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

    test('completing a token mid-line preserves the tail', () {
      const text = 'sou leveling';
      final t = activeTokenAt(text, 3);
      final s = suggestFor(t, _facets).firstWhere((e) => e.display == 'source:');
      final r = applySuggestion(text, t, s);
      expect(r.text, 'source: leveling');
      expect(r.caret, 7);
    });

    test('negation prefix is preserved on completion', () {
      final t = activeTokenAt('-source:man', 11);
      final s = suggestFor(t, _facets).single;
      final r = applySuggestion('-source:man', t, s);
      expect(r.text, '-source:MangaDex ');
    });
  });
}
