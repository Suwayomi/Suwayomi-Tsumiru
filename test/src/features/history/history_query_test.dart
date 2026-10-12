import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:tsumiru/src/features/history/data/graphql/__generated__/query.graphql.dart';

void main() {
  test('history asks only for the series fields a row shows', () {
    // Up to 2000 chapters come back in one fetch; a full series on each made
    // it ~3.8 MB.
    final manga = printNode(documentNodeQueryGetReadingHistory)
        .split('manga {')
        .last
        .split('}')
        .first;
    for (final field in ['description', 'genre', 'realUrl', 'meta']) {
      expect(manga, isNot(contains(field)), reason: field);
    }
    expect(manga, contains('title'));
    expect(manga, contains('thumbnailUrl'));
  });
}
