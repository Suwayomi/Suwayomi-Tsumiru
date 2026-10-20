import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_server_identity.dart';

void main() {
  group('serverIdentity', () {
    test('normalizes trailing paths and the effective port', () {
      expect(
        serverAddress(
          baseUrl: 'https://reader.example.test/path/',
          port: 4567,
          addPort: true,
        ),
        'https://reader.example.test:4567',
      );
    });
  });

  test('catalog is parked on another server and restored on return', () {
    const serverA = 'https://a.example.test:443';
    const serverB = 'https://b.example.test:443';

    expect(
      isOfflineCatalogActive(
        offlineEnabled: true,
        catalogServer: serverA,
        currentServer: serverA,
      ),
      isTrue,
    );
    expect(
      isOfflineCatalogActive(
        offlineEnabled: true,
        catalogServer: serverA,
        currentServer: serverB,
      ),
      isFalse,
    );
    expect(
      isOfflineCatalogActive(
        offlineEnabled: true,
        catalogServer: serverA,
        currentServer: serverA,
      ),
      isTrue,
    );
  });
}
