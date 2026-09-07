import 'dart:convert';
import 'dart:io';

import 'background_download_lock.dart';
import 'background_work_order.dart';

const kAcceptedWorkOrderKey = 'offline_download_accepted_order';

Future<T> withWorkOrderAdmission<T>(
  String baseDir,
  Future<T> Function() action,
) async {
  final lock = BackgroundDownloadLock(File('$baseDir/.bg_admission'));
  for (var i = 0; i < 600; i++) {
    if (await lock.acquire('admission')) {
      try {
        return await action();
      } finally {
        await lock.release();
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Download work order is busy');
}

BackgroundWorkOrder? decodeWorkOrder(String? raw) => raw == null
    ? null
    : BackgroundWorkOrder.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
