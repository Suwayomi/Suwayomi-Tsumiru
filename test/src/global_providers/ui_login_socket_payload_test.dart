// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  test(
    'a session change before or during the read aborts the connect',
    () async {
      await expectLater(
        uiLoginSocketPayload(
          isCurrentSession: () => false,
          refreshIfDue: () async {},
          readToken: () async => 'token',
        ),
        throwsStateError,
      );
      var current = true;
      await expectLater(
        uiLoginSocketPayload(
          isCurrentSession: () => current,
          refreshIfDue: () async {},
          readToken: () async {
            current = false;
            return 'token';
          },
        ),
        throwsStateError,
      );
    },
  );
}
