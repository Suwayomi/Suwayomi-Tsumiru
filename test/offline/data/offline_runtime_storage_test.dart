import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';

import '../../helpers/offline_test_db.dart';

void main() {
  late Directory root;
  late ProviderContainer container;
  late OfflineRuntimeStorage runtime;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('offline-account-runtime-');
    container = ProviderContainer();
    runtime = container.read(offlineRuntimeStorageProvider.notifier);
  });
  tearDown(() async {
    await runtime.replace(drain: () async {}, open: () async => null);
    container.dispose();
  });
  Future<OfflineStorage> open(String account) async {
    final directory = Directory('${root.path}/$account');
    await directory.create();
    final paths = OfflinePaths(directory.path);
    return (
      db: testOfflineDatabaseFile('${directory.path}/catalog.sqlite'),
      paths: paths,
      store: IoOfflinePageStore(paths),
    );
  }

  test('drains A writes before B opens and restores A on return', () async {
    await runtime.replace(drain: () async {}, open: () => open('A'));
    final a = container.read(offlineRuntimeStorageProvider)!;
    final writing = Completer<void>();
    final release = Completer<void>();
    final write = () async {
      writing.complete();
      await release.future;
      await a.db.upsertMangaMetadata(
        id: 1,
        title: 'A private title',
        updatedAt: DateTime(2026),
      );
    }();
    await writing.future;
    var openedB = false;
    final switchToB = runtime.replace(
      drain: () => write,
      open: () async {
        openedB = true;
        return open('B');
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(openedB, isFalse);
    release.complete();
    await switchToB;
    final b = container.read(offlineRuntimeStorageProvider)!;
    expect(await b.db.mangaById(1), isNull);
    await b.db.upsertMangaMetadata(
      id: 1,
      title: 'B private title',
      updatedAt: DateTime(2026),
    );
    await runtime.replace(drain: () async {}, open: () => open('A'));
    expect(
      (await container.read(offlineRuntimeStorageProvider)!.db.mangaById(1))
          ?.title,
      'A private title',
    );
  });
  test('tracked account writes drain before closing their database', () async {
    await runtime.replace(drain: () async {}, open: () => open('A'));
    final a = container.read(offlineRuntimeStorageProvider)!;
    final release = Completer<void>();
    final write = runtime.track(() async {
      await release.future;
      await a.db.upsertMangaMetadata(
        id: 1,
        title: 'A',
        updatedAt: DateTime(2026),
      );
    });
    final switching = runtime.replace(
      drain: runtime.drain,
      open: () => open('B'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(offlineRuntimeStorageProvider), same(a));
    release.complete();
    await write;
    await switching;
    expect(
      await container.read(offlineRuntimeStorageProvider)!.db.mangaById(1),
      isNull,
    );
    await runtime.replace(drain: runtime.drain, open: () => open('A'));
    expect(
      (await container.read(offlineRuntimeStorageProvider)!.db.mangaById(1))
          ?.title,
      'A',
    );
  });

  test('refused drain leaves A usable and never opens B', () async {
    await runtime.replace(drain: () async {}, open: () => open('A'));
    final a = container.read(offlineRuntimeStorageProvider)!;
    await expectLater(
      runtime.replace(
        drain: () async => throw StateError('Worker busy'),
        open: () async => throw StateError('must not open'),
      ),
      throwsStateError,
    );
    expect(container.read(offlineRuntimeStorageProvider), same(a));
    expect(await a.db.mangaById(1), isNull);
  });
  test('failed open exposes no old account and permits retry', () async {
    await runtime.replace(drain: () async {}, open: () => open('A'));
    await expectLater(
      runtime.replace(
        drain: () async {},
        open: () async => throw FileSystemException('Unavailable'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(container.read(offlineRuntimeStorageProvider), isNull);
    await runtime.replace(drain: () async {}, open: () => open('A'));
    expect(container.read(offlineRuntimeStorageProvider), isNotNull);
  });
  test('overlapping storage changes are refused', () async {
    final gate = Completer<void>();
    final switching = runtime.replace(
      drain: () => gate.future,
      open: () => open('A'),
    );
    await expectLater(
      runtime.replace(drain: () async {}, open: () => open('B')),
      throwsStateError,
    );
    gate.complete();
    await switching;
    expect(
      container.read(offlineRuntimeStorageProvider)!.paths.baseDir,
      endsWith('/A'),
    );
  });
}
