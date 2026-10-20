import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';

void main() {
  test('library defaults: last read sort, descending, no downloaded badge', () {
    expect(DBKeys.mangaSort.initial, MangaSort.lastRead);
    // The lastRead comparator is ascending = oldest-read first, so the
    // default direction is descending to open newest-read first.
    expect(DBKeys.mangaSortDirection.initial, false);
    expect(DBKeys.downloadedBadge.initial, false);
  });
}
