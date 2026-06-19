import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/constants/enum.dart';

void main() {
  test('default library sort is Last Read', () {
    expect(DBKeys.mangaSort.initial, MangaSort.lastRead);
  });

  test('default sort direction stays ascending-toggle (most-recent-first for lastRead)', () {
    expect(DBKeys.mangaSortDirection.initial, true);
  });
}
