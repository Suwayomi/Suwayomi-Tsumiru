import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/about/data/server_update_alerts_repository.dart';

void main() {
  test('Remind later hides updates for one hour', () {
    final hour = updateCheckInterval.inMilliseconds;
    expect(
      shouldShowUpdate(
        version: 'v2',
        ignoredVersion: null,
        closedTimestamp: hour,
        now: 2 * hour - 1,
      ),
      isFalse,
    );
    expect(
      shouldShowUpdate(
        version: 'v2',
        ignoredVersion: null,
        closedTimestamp: hour,
        now: 2 * hour,
      ),
      isTrue,
    );
  });

  test('Ignore hides only the selected version', () {
    final now = 2 * updateCheckInterval.inMilliseconds;
    expect(
      shouldShowUpdate(
        version: 'v2',
        ignoredVersion: 'v2',
        closedTimestamp: 0,
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldShowUpdate(
        version: 'v3',
        ignoredVersion: 'v2',
        closedTimestamp: 0,
        now: now,
      ),
      isTrue,
    );
  });
}
