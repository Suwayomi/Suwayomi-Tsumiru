import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity_repository.dart';

void main() {
  test('creates missing identity and trusts the value read back', () async {
    var reads = 0;
    String? written;

    final result = await resolveServerInstanceId(
      read: () async => reads++ == 0 ? null : 'server-value',
      write: (value) async => written = value,
      create: () => 'candidate-value',
    );

    expect(written, 'candidate-value');
    expect(result, 'server-value');
  });

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
