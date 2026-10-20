import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';

void main() {
  group('selectServerUrl', () {
    const external = 'https://suwayomi.example.com';
    const lan = 'http://192.168.1.100:4567';

    test('prefers a reachable LAN URL, else the external URL', () async {
      expect(
        await selectServerUrl(
          externalUrl: external,
          lanUrl: null,
          isReachable: (_) async => throw StateError('should not probe'),
        ),
        external,
      );
      expect(
        await selectServerUrl(
          externalUrl: external,
          lanUrl: lan,
          isReachable: (url) async => url == lan,
        ),
        lan,
      );
    });

    test('falls back to the external URL when the LAN URL is unavailable, '
        'normalising it before probing', () async {
      expect(
        await selectServerUrl(
          externalUrl: external,
          lanUrl: lan,
          isReachable: (_) async => false,
        ),
        external,
      );

      var probed = '';
      await selectServerUrl(
        externalUrl: external,
        lanUrl: '$lan/',
        isReachable: (url) async {
          probed = url;
          return false;
        },
      );
      expect(probed, lan);
    });
  });
}
