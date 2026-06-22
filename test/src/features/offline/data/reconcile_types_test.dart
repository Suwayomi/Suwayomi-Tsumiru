import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_types.dart';

void main() {
  test('SafetyNetConfig.off is all-disabled', () {
    expect(SafetyNetConfig.off.timeEvictEnabled, false);
    expect(SafetyNetConfig.off.storageCapEnabled, false);
  });
  test('ReconcilePlan.empty has empty sets and no warning', () {
    expect(ReconcilePlan.empty.toDownload, isEmpty);
    expect(ReconcilePlan.empty.toEvict, isEmpty);
    expect(ReconcilePlan.empty.overCapWarning, false);
  });
}
