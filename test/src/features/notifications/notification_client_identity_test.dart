import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';

void main() {
  const a = BackgroundTokenRecord(
    gen: 0,
    authType: 'uiLogin',
    endpoint: 'https://server',
    accessToken: 'A',
    refreshToken: 'R-A',
    originalRefreshToken: 'R-A',
    identityEpoch: 1,
    catalogServerId: 'a',
  );
  const b = BackgroundTokenRecord(
    gen: 0,
    authType: 'uiLogin',
    endpoint: 'https://server',
    accessToken: 'B',
    refreshToken: 'R-B',
    originalRefreshToken: 'R-B',
    identityEpoch: 2,
    catalogServerId: 'b',
  );

  for (final mismatchedAtStart in [false, true]) {
    test(
      'notification retry rejects another account: initial mismatch=$mismatchedAtStart',
      () async {
        var reads = 0;
        final sent = <String?>[];
        final client = NotificationBackgroundClient(
          endpoint: const NotificationEndpoint(
            baseUrl: 'https://server',
            addPort: false,
          ),
          record: a,
          broker: TokenBroker(
            expectedIdentity: mismatchedAtStart ? b : a,
            read: () async => mismatchedAtStart || ++reads >= 3 ? b : a,
            write: (_) async {},
            refreshFn: (_) async =>
                (tokens: (access: 'A2', refresh: 'R-A2'), transient: false),
          ),
          httpClient: MockClient((request) async {
            sent.add(request.headers['Authorization']);
            return http.Response('', 401);
          }),
        );
        expect(await client.markRead([1]), isFalse);
        expect(sent, ['Bearer A']);
        expect(client.currentRecord().sameIdentity(a), isTrue);
      },
    );
  }
}
