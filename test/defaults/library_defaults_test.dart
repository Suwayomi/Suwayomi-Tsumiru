import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';

void main() {
  test('default library sort is Last Read', () {
    expect(DBKeys.mangaSort.initial, MangaSort.lastRead);
  });

  test('default sort direction is descending (newest-read first for lastRead)', () {
    // The lastRead comparator is now ascending = oldest-read
    // first, so the default direction is descending to keep the library
    // opening newest-read first.
    expect(DBKeys.mangaSortDirection.initial, false);
  });

  test('downloaded badge is off by default', () {
    expect(DBKeys.downloadedBadge.initial, false);
  });
}
