import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a newer denial defeats an older grant and remains account scoped',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = CatchupStateStore(await SharedPreferences.getInstance());
      final dir = await Directory.systemTemp.createTemp('permission-state');
      expect(
        await state.recordDownloadPermission(
          'A',
          allowed: false,
          expectedRevision: 0,
          isCurrent: () => true,
          baseDir: dir.path,
        ),
        isTrue,
      );
      expect(state.downloadPermissionRevision('A'), 1);
      expect(
        await state.recordDownloadPermission(
          'A',
          allowed: true,
          expectedRevision: 0,
          isCurrent: () => true,
          baseDir: dir.path,
        ),
        isFalse,
      );
      expect(state.downloadPermissionPaused('A'), isTrue);
      expect(state.downloadPermissionPaused('B'), isFalse);
      expect(
        await state.recordDownloadPermission(
          'A',
          allowed: true,
          expectedRevision: 1,
          isCurrent: () => false,
          baseDir: dir.path,
        ),
        isFalse,
      );
      expect(
        await state.recordDownloadPermission(
          'A',
          allowed: true,
          expectedRevision: 1,
          isCurrent: () => true,
          baseDir: dir.path,
        ),
        isTrue,
      );
      expect(state.downloadPermissionPaused('A'), isFalse);
    },
  );
}
