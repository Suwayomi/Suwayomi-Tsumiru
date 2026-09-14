import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';

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
  });

  test('a failed drain preserves catalog rows, files and identity', () async {
    final events = <String>[];
    await expectLater(
      clearOfflineCatalogWithDependencies(
        stopBackground: () async => events.add('background'),
        stopMainPump: () async => throw StateError('Downloads did not stop'),
        clearDatabase: () async => events.add('database'),
        clearFiles: () async => events.add('files'),
        clearIdentity: () async => events.add('identity'),
        finish: () => events.add('finish'),
      ),
      throwsStateError,
    );
    expect(events, ['background', 'finish']);
  });

  test('restart suppression is released when a wipe fails', () async {
    var finished = false;

    await expectLater(
      clearOfflineCatalogWithDependencies(
        stopBackground: () async {},
        stopMainPump: () async {},
        clearDatabase: () async => throw StateError('wipe failed'),
        clearFiles: () async {},
        clearIdentity: () async {},
        finish: () => finished = true,
      ),
      throwsStateError,
    );
    expect(finished, isTrue);
  });
}
