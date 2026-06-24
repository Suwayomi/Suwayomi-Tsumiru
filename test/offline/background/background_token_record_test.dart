import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';

void main() {
  test('a newer record gen is used WITHOUT calling refresh', () async {
    var record = const BackgroundTokenRecord(
        gen: 1, authType: 'uiLogin', accessToken: 'OLD', refreshToken: 'R0');
    var refreshCalls = 0;
    final broker = TokenBroker(
      read: () async => record,
      write: (r) async => record = r,
      refreshFn: (_) async {
        refreshCalls++;
        return (access: 'NEW', refresh: 'R1');
      },
    );
    // someone else already advanced the record:
    record = const BackgroundTokenRecord(
        gen: 2, authType: 'uiLogin', accessToken: 'NEWER', refreshToken: 'R9');
    final token = await broker.resolveAfter401('OLD');
    expect(token, 'NEWER');
    expect(refreshCalls, 0);
  });

  test('refresh rotates BOTH tokens and bumps gen', () async {
    var record = const BackgroundTokenRecord(
        gen: 1, authType: 'uiLogin', accessToken: 'OLD', refreshToken: 'R0');
    final broker = TokenBroker(
      read: () async => record,
      write: (r) async => record = r,
      refreshFn: (rt) async {
        expect(rt, 'R0');
        return (access: 'NEW', refresh: 'R1');
      },
    );
    final token = await broker.resolveAfter401('OLD');
    expect(token, 'NEW');
    expect(record.gen, 2);
    expect(record.accessToken, 'NEW');
    expect(record.refreshToken, 'R1'); // rotated refresh persisted (fixes C4)
  });

  test('a dead refresh returns null', () async {
    var record = const BackgroundTokenRecord(
        gen: 1, authType: 'uiLogin', accessToken: 'OLD', refreshToken: 'R0');
    final broker = TokenBroker(
      read: () async => record,
      write: (r) async => record = r,
      refreshFn: (_) async => null,
    );
    expect(await broker.resolveAfter401('OLD'), isNull);
  });
}
