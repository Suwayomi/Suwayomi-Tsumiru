import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/offline/data/background/catchup_work_spec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('handover reloads attempts persisted by another isolate', () async {
    SharedPreferences.setMockInitialValues({
      DBKeys.offlineCatalogServerId.name: 'A',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = CatchupStateStore(preferences);
    await store.writeLedger(
      'A',
      const CatchupLedger(queuedServerRetries: {'1:0': 4}),
    );
    SharedPreferences.setMockInitialValues({
      DBKeys.offlineCatalogServerId.name: 'A',
      'catchup_ledger/A': jsonEncode({
        'serverId': 'A',
        'ledger': const CatchupLedger(queuedServerRetries: {'1:0': 5}).toJson(),
      }),
    });
    expect(store.readLedger('A').queuedServerRetries, {'1:0': 4});
    await store.clearState(preserveLedger: true);
    expect(store.readLedger('A').queuedServerRetries, {'1:0': 5});
  });

  test('account replacement retains each catalogue retry history', () async {
    SharedPreferences.setMockInitialValues({
      DBKeys.offlineCatalogServerId.name: 'A',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = CatchupStateStore(preferences);
    await store.writeLedger(
      'A',
      const CatchupLedger(queuedServerRetries: {'1:0': 5}),
    );
    await store.clearState(preserveLedger: true);
    await preferences.setString(DBKeys.offlineCatalogServerId.name, 'B');
    await store.writeLedger(
      'B',
      const CatchupLedger(queuedServerRetries: {'1:0': 2}),
    );
    await store.clearState(preserveLedger: true);
    expect(store.readLedger('A').queuedServerRetries, {'1:0': 5});
    expect(store.readLedger('B').queuedServerRetries, {'1:0': 2});
    await store.clearState();
    expect(store.readLedger('B').queuedServerRetries, isEmpty);
    expect(store.readLedger('A').queuedServerRetries, {'1:0': 5});
  });

  test(
    'endpoint handover preserves legacy exhausted device attempts',
    () async {
      SharedPreferences.setMockInitialValues({
        DBKeys.offlineCatalogServerId.name: 'A',
        'catchup_ledger': jsonEncode({
          'serverId': 'A',
          'ledger': const CatchupLedger(
            queuedDownloadRetries: {'1:3': 5},
          ).toJson(),
        }),
      });
      final preferences = await SharedPreferences.getInstance();
      final store = CatchupStateStore(preferences);
      await store.clearState(preserveLedger: true);
      expect(store.readLedger('A').queuedDownloadRetries, {'1:3': 5});
      expect(store.readLedger('B').queuedDownloadRetries, isEmpty);
      await store.clearState();
      expect(store.readLedger('A').queuedDownloadRetries, isEmpty);
    },
  );
}
