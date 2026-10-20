import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';

void main() {
  const owner = BackgroundTokenRecord(
    gen: 1,
    authType: 'uiLogin',
    endpoint: 'https://server',
    accessToken: 'A',
    refreshToken: 'refresh-a',
    identityEpoch: 4,
    catalogServerId: 'account-a',
    originalRefreshToken: 'refresh-a',
  );
  const other = BackgroundTokenRecord(
    gen: 2,
    authType: 'uiLogin',
    endpoint: 'https://server',
    accessToken: 'B',
    refreshToken: 'refresh-b',
    identityEpoch: 5,
    catalogServerId: 'account-b',
    originalRefreshToken: 'refresh-b',
  );

  test('rotation uses a newer record, rotates both tokens, bumps gen and '
      'keeps identity proof', () async {
    var record = const BackgroundTokenRecord(
      gen: 1,
      authType: 'uiLogin',
      accessToken: 'OLD',
      refreshToken: 'R0',
    );
    var refreshCalls = 0;
    final broker = TokenBroker(
      read: () async => record,
      write: (r) async => record = r,
      refreshFn: (_) async {
        refreshCalls++;
        return (tokens: (access: 'NEW', refresh: 'R1'), transient: false);
      },
    );

    // Someone else already advanced the record: use it without refreshing.
    record = const BackgroundTokenRecord(
      gen: 2,
      authType: 'uiLogin',
      accessToken: 'NEWER',
      refreshToken: 'R9',
    );
    expect(await broker.resolveAfter401('OLD'), 'NEWER');
    expect(refreshCalls, 0);

    record = const BackgroundTokenRecord(
      gen: 1,
      authType: 'uiLogin',
      accessToken: 'OLD',
      refreshToken: 'R0',
    );
    expect(await broker.resolveAfter401('OLD'), 'NEW');
    expect(record.gen, 2);
    expect(record.accessToken, 'NEW');
    expect(record.refreshToken, 'R1');

    final rotated = owner.copyWith(
      gen: 2,
      accessToken: 'A2',
      refreshToken: 'rotated',
    );
    final restored = BackgroundTokenRecord.fromJson(rotated.toJson());
    expect(restored.sameIdentity(owner), isTrue);
    expect(restored.identityEpoch, 4);
    expect(restored.catalogServerId, 'account-a');
    expect(restored.originalRefreshToken, 'refresh-a');
    expect(restored.refreshToken, 'rotated');
    expect(restored.sameIdentity(other), isFalse);
  });

  test(
    'same endpoint account replacement is rejected before refresh',
    () async {
      var calls = 0;
      final broker = TokenBroker(
        expectedIdentity: owner,
        read: () async => other,
        write: (_) async {
          fail('must not write');
        },
        refreshFn: (_) async {
          calls++;
          return (
            tokens: (access: 'new', refresh: 'new-refresh'),
            transient: false,
          );
        },
      );
      broker.lastRefreshTransient = true;
      expect(await broker.resolveAfter401('A'), isNull);
      expect(calls, 0);
      expect(broker.lastRefreshTransient, isFalse);
    },
  );
}
