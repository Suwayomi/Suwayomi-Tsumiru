import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';

void main() {
  test('clearAll deletes pages and covers but preserves the catalog', () async {
    final temp = await Directory.systemTemp.createTemp('tsumiru-offline-');
    addTearDown(() => temp.delete(recursive: true));
    final paths = OfflinePaths(temp.path);
    final store = IoOfflinePageStore(paths);
    final catalog = File('${temp.path}/catalog.sqlite');
    await catalog.writeAsString('catalog');
    await store.writePage(12, 34, 0, [1, 2, 3], 'jpg');
    final cover = File(paths.absolute('covers/12.jpg'));
    await cover.parent.create(recursive: true);
    await cover.writeAsBytes([1]);

    await store.clearAll();

    expect(await catalog.exists(), isTrue);
    expect(await Directory(paths.absolute('12')).exists(), isFalse);
    expect(await Directory(paths.absolute('covers')).exists(), isFalse);
  });
}
