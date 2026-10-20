import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/connection/connection_status.dart';

void main() {
  group('formatServerHost', () {
    test(
      'strips scheme and trailing slash, and appends the port when asked',
      () {
        expect(
          formatServerHost('http://myserver.local', 4567, true),
          'myserver.local:4567',
        );
        expect(
          formatServerHost('http://myserver.local', 4567, false),
          'myserver.local',
        );
        expect(
          formatServerHost('https://manga.example.com', 443, true),
          'manga.example.com:443',
        );
        expect(
          formatServerHost('http://192.168.2.5/', 4567, true),
          '192.168.2.5:4567',
        );
        expect(formatServerHost(null, 4567, true), '');
        expect(formatServerHost('', 4567, true), '');
        expect(formatServerHost('http://host', null, true), 'host');
      },
    );
  });

  group('connectionAuthStatus', () {
    test('reauth wins, then no-auth, then signed in', () {
      expect(
        connectionAuthStatus(AuthType.basic, true),
        ConnectionAuthStatus.signInNeeded,
      );
      expect(
        connectionAuthStatus(AuthType.none, true),
        ConnectionAuthStatus.signInNeeded,
      );
      expect(
        connectionAuthStatus(AuthType.none, false),
        ConnectionAuthStatus.noAuth,
      );
      expect(connectionAuthStatus(null, false), ConnectionAuthStatus.noAuth);
      expect(
        connectionAuthStatus(AuthType.basic, false),
        ConnectionAuthStatus.signedIn,
      );
      expect(
        connectionAuthStatus(AuthType.simpleLogin, false),
        ConnectionAuthStatus.signedIn,
      );
      expect(
        connectionAuthStatus(AuthType.uiLogin, false),
        ConnectionAuthStatus.signedIn,
      );
    });
  });
}
