import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/background/background_work_order.dart';

void main() {
  test('work order round-trips through json incl. int-keyed maps', () {
    final order = BackgroundWorkOrder(
      chapterIds: const [5, 6, 7],
      mangaIdByChapter: const {5: 1, 6: 1, 7: 2},
      serverBase: 'https://suwayomi.example',
      port: 4567,
      addPort: false,
      wifiOnly: true,
      auth: const BackgroundTokenRecord(
          gen: 3, authType: 'uiLogin', accessToken: 'A', refreshToken: 'R'),
      baseDir: '/data/app/offline',
      rootIsolateToken: 99887766,
    );
    final restored = BackgroundWorkOrder.fromJson(order.toJson());
    expect(restored.chapterIds, [5, 6, 7]);
    expect(restored.mangaIdByChapter[6], 1);
    expect(restored.mangaIdByChapter[7], 2);
    expect(restored.wifiOnly, isTrue);
    expect(restored.auth.gen, 3);
    expect(restored.auth.accessToken, 'A');
    expect(restored.baseDir, '/data/app/offline');
    expect(restored.rootIsolateToken, 99887766);
  });

  test('baseDir defaults to empty when absent (back-compat decode)', () {
    final order = BackgroundWorkOrder(
      chapterIds: const [1],
      mangaIdByChapter: const {1: 1},
      serverBase: 'https://s.example',
      port: null,
      addPort: false,
      wifiOnly: false,
      auth: const BackgroundTokenRecord(gen: 0, authType: 'none'),
      baseDir: '/x',
    );
    final json = order.toJson()..remove('baseDir');
    final restored = BackgroundWorkOrder.fromJson(json);
    expect(restored.baseDir, '');
    expect(restored.rootIsolateToken, 0);
  });
}
