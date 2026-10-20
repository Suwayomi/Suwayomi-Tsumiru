import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';

void main() {
  test('uses a same-address cached identity only on connection loss', () {
    expect(
      cachedServerIdForFailure(
        error: const SocketException('offline'),
        currentAddress: 'https://reader.test:443',
        cachedAddress: 'https://reader.test:443',
        cachedId: 'cached-id',
      ),
      'cached-id',
    );
    expect(
      cachedServerIdForFailure(
        error: StateError('metadata write failed'),
        currentAddress: 'https://reader.test:443',
        cachedAddress: 'https://reader.test:443',
        cachedId: 'cached-id',
      ),
      isNull,
    );
  });
}
