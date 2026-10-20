// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// v1.2.0 would not start under Flatpak. The sandbox has no system D-Bus, so
// connectivity_plus failed while reaching NetworkManager. That failure lands
// after listen() returns, escaped the try/catch around it, and an uncaught
// async error before the first frame shows the "couldn't start" screen.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';

void main() {
  test(
    'a connectivity stream failure never crashes and the stream survives',
    () async {
      final controller = StreamController<List<ConnectivityResult>>();
      final zoneErrors = <Object>[];
      var changes = 0;
      late StreamSubscription<List<ConnectivityResult>> sub;

      await runZonedGuarded(() async {
        sub = listenToConnectivity(controller.stream, () => changes++);
        controller.addError(const SocketException('no system bus'));
        await pumpEventQueue();
        // Later connectivity changes still arrive.
        controller.add([ConnectivityResult.wifi]);
        await pumpEventQueue();
        await sub.cancel();
      }, (error, _) => zoneErrors.add(error));

      expect(
        zoneErrors,
        isEmpty,
        reason:
            'an unreachable NetworkManager must not become a fatal startup '
            'error the way it did under Flatpak in v1.2.0',
      );
      expect(changes, 1, reason: 'the subscription must survive an error');
    },
  );
}

class SocketException implements Exception {
  const SocketException(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}
