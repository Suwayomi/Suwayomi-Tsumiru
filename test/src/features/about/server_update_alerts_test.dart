// Launch triggers for WebUI's server-update notices, mirroring
// ServerUpdateChecker: first sighting records silently, a changed version
// notifies when its switch is on, and the available-update network check
// runs only when its switch is on. Pure logic, no providers involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/about/data/server_update_alerts_repository.dart';

void main() {
  test('first launch records the version without notifying', () {
    final decision = decideServerUpdateAlerts(
      canManage: true,
      currentVersion: 'v2.4.2366',
      lastSeenVersion: null,
      informVersionUpdated: true,
      informAvailableUpdate: true,
    );
    expect(decision.showUpdatedNotice, isFalse);
    expect(decision.storeVersion, isTrue);
    expect(decision.checkAvailable, isTrue);
  });

  test('changed version notifies when on and records silently when off', () {
    final noticed = decideServerUpdateAlerts(
      canManage: true,
      currentVersion: 'v2.4.2400',
      lastSeenVersion: 'v2.4.2366',
      informVersionUpdated: true,
      informAvailableUpdate: true,
    );
    expect(noticed.showUpdatedNotice, isTrue);
    expect(noticed.storeVersion, isTrue);
    expect(noticed.checkAvailable, isTrue);

    final silent = decideServerUpdateAlerts(
      canManage: true,
      currentVersion: 'v2.4.2400',
      lastSeenVersion: 'v2.4.2366',
      informVersionUpdated: false,
      informAvailableUpdate: false,
    );
    expect(silent.showUpdatedNotice, isFalse);
    expect(silent.storeVersion, isTrue);
    expect(silent.checkAvailable, isFalse);
  });

  test('unchanged versions and missing permission stay silent', () {
    final same = decideServerUpdateAlerts(
      canManage: true,
      currentVersion: 'v2.4.2366',
      lastSeenVersion: 'v2.4.2366',
      informVersionUpdated: true,
      informAvailableUpdate: true,
    );
    expect(same.showUpdatedNotice, isFalse);
    expect(same.storeVersion, isFalse);
    expect(same.checkAvailable, isTrue);

    for (final decision in [
      decideServerUpdateAlerts(
        canManage: false,
        currentVersion: 'v2.4.2400',
        lastSeenVersion: 'v2.4.2366',
        informVersionUpdated: true,
        informAvailableUpdate: true,
      ),
      decideServerUpdateAlerts(
        canManage: true,
        currentVersion: '',
        lastSeenVersion: 'v2.4.2366',
        informVersionUpdated: true,
        informAvailableUpdate: true,
      ),
    ]) {
      expect(decision.showUpdatedNotice, isFalse);
      expect(decision.storeVersion, isFalse);
      expect(decision.checkAvailable, isFalse);
    }
  });

  test('only a parsable newer tag counts as an available update', () {
    expect(isNewerServerVersion('v2.4.2366', 'v2.4.2400'), isTrue);
    expect(isNewerServerVersion('v2.4.2366', 'v2.4.2366'), isFalse);
    expect(isNewerServerVersion('v2.4.2400', 'v2.4.2366'), isFalse);
    expect(isNewerServerVersion('v2.4.2366', null), isFalse);
    expect(isNewerServerVersion('v2.4.2366', ''), isFalse);
    expect(isNewerServerVersion('v2.4.2366', 'not-a-version'), isFalse);
    expect(isNewerServerVersion('not-a-version', 'v2.4.2400'), isFalse);
  });
}
