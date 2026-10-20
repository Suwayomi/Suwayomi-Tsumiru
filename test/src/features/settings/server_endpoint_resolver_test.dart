import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';

void main() {
  group('selectServerUrl', () {
    const external = 'https://suwayomi.example.com';
    const lan = 'http://192.168.1.100:4567';

    test('prefers a reachable LAN URL, else falls back to the external URL', () async {
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
      expect(
        await selectServerUrl(
          externalUrl: external,
          lanUrl: lan,
          isReachable: (_) async => false,
        ),
        external,
      );

      // The fallback normalises the LAN URL before probing it.
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
