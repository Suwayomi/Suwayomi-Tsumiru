import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';

void main() {
  test('workers stop before catalog rows and files are cleared', () async {
    final events = <String>[];

    await clearOfflineCatalogWithDependencies(
      stopBackground: () async => events.add('background'),
      stopMainPump: () async => events.add('main'),
      clearDatabase: () async => events.add('database'),
      clearFiles: () async => events.add('files'),
      clearIdentity: () async => events.add('identity'),
      finish: () => events.add('finish'),
    );

    expect(events, [
      'background',
      'main',
      'database',
      'files',
      'identity',
      'finish',
    ]);

    // A refused drain stops the wipe at the first step and still releases
    // the restart suppression.
    final failed = <String>[];
    await expectLater(
      clearOfflineCatalogWithDependencies(
        stopBackground: () async => failed.add('background'),
        stopMainPump: () async => throw StateError('Downloads did not stop'),
        clearDatabase: () async => failed.add('database'),
        clearFiles: () async => failed.add('files'),
        clearIdentity: () async => failed.add('identity'),
        finish: () => failed.add('finish'),
      ),
      throwsStateError,
    );
    expect(failed, ['background', 'finish']);

    // clearAll is one destructive path: pages and covers go, the catalog stays.
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
