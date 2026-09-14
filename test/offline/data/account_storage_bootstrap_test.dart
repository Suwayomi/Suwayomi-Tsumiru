import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tsumiru/src/features/offline/data/offline_bootstrap.dart';

class _Support extends PathProviderPlatform {
  _Support(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a different user cannot open a reused catalogue identity', () async {
    final root = await Directory.systemTemp.createTemp('account-owner-');
    PathProviderPlatform.instance = _Support(root.path);
    final a = (await initOfflineStorage(
      accountId: 'shared-id',
      accountOwner: '1',
    ))!;
    await a.db.upsertMangaMetadata(
      id: 1,
      title: 'A',
      updatedAt: DateTime(2026),
    );
    await a.db.close();
    await expectLater(
      initOfflineStorage(accountId: 'shared-id', accountOwner: '2'),
      throwsStateError,
    );
    final restored = (await initOfflineStorage(
      accountId: 'shared-id',
      accountOwner: '1',
    ))!;
    expect((await restored.db.mangaById(1))?.title, 'A');
    await restored.db.close();
  });

  test(
    'native bootstrap preserves A data while opening B and returning to A',
    () async {
      final root = await Directory.systemTemp.createTemp('account-bootstrap-');
      PathProviderPlatform.instance = _Support(root.path);
      final a = (await initOfflineStorage(accountId: 'A'))!;
      await a.db.upsertMangaMetadata(
        id: 1,
        title: 'A',
        updatedAt: DateTime(2026),
      );
      await a.db.close();
      final b = (await initOfflineStorage(accountId: 'B'))!;
      expect(await b.db.mangaById(1), isNull);
      await b.db.close();
      final restored = (await initOfflineStorage(accountId: 'A'))!;
      expect((await restored.db.mangaById(1))?.title, 'A');
      await restored.db.close();
    },
  );
}
