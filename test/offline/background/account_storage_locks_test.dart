import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_paths.dart';
import 'package:tsumiru/src/features/offline/data/background/background_schedule.dart';
import 'package:tsumiru/src/features/offline/data/background/work_order_admission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final schedule in [false, true]) {
    test(
      'account directories share ${schedule ? 'schedule' : 'admission'} ownership',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'account-shared-lock-',
        );
        final entered = Completer<void>();
        final release = Completer<void>();
        Future<void> lock(String path, Future<void> Function() action) =>
            schedule
            ? withBackgroundScheduleLock(action, baseDir: path)
            : withWorkOrderAdmission(path, action);
        final first = lock(accountStoragePath(root.path, 'A'), () async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        var secondEntered = false;
        final second = lock(
          accountStoragePath(root.path, 'B'),
          () async => secondEntered = true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(secondEntered, isFalse);
        release.complete();
        await Future.wait([first, second]);
        expect(secondEntered, isTrue);
        expect(offlineControlRoot(root.path), root.path);
        expect(
          offlineControlRoot(accountStoragePath(root.path, 'A')),
          root.path,
        );
      },
    );
  }
}
