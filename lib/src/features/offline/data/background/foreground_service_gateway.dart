// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../../utils/logger/logger.dart';
import 'background_work_order.dart';
import 'download_task_handler.dart';

class ForegroundServiceGateway {
  Future<bool> get isRunningService => FlutterForegroundTask.isRunningService;

  Future<ServiceRequestResult> start() => FlutterForegroundTask.startService(
    serviceTypes: [ForegroundServiceTypes.dataSync],
    notificationTitle: 'Downloading chapters',
    notificationText: 'Starting…',
    notificationIcon: const NotificationIcon(
      metaDataName: kNotificationIconMetaData,
    ),
    callback: backgroundDownloadCallback,
  );

  Future<ServiceRequestResult> stop() => FlutterForegroundTask.stopService();

  void send(Object data) => FlutterForegroundTask.sendDataToTask(data);

  Future<String?> read(String key) =>
      FlutterForegroundTask.getData<String>(key: key);

  Future<void> write(String key, String value) async {
    if (!await FlutterForegroundTask.saveData(key: key, value: value)) {
      throw StateError('Failed to save foreground service data: $key');
    }
  }

  Future<void> remove(String key) async {
    if (!await FlutterForegroundTask.removeData(key: key)) {
      throw StateError('Failed to remove foreground service data: $key');
    }
  }

  void addCallback(DataCallback callback) =>
      FlutterForegroundTask.addTaskDataCallback(callback);

  void removeCallback(DataCallback callback) =>
      FlutterForegroundTask.removeTaskDataCallback(callback);

  Future<void> ensureNotificationPermission() async {
    final current = await FlutterForegroundTask.checkNotificationPermission();
    if (current == NotificationPermission.granted) return;
    final result = await FlutterForegroundTask.requestNotificationPermission();
    if (result != NotificationPermission.granted) {
      logger.i('Offline: notification permission not granted ($result)');
    }
  }
}
