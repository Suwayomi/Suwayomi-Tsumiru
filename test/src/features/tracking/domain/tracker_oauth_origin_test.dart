import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/tracking/domain/tracker_oauth_origin.dart';

void main() {
  test(
    'configured origin strips secrets but preserves path, port, auth and username case',
    () {
      final first = trackerOAuthOrigin(
        mode: AuthType.basic,
        configuredServer:
            'HTTPS://user:password@Example.test:8443/base?token=secret#fragment',
        username: ' Reader ',
      );
      expect(first, '["basic","https://example.test:8443/base","Reader"]');
      expect(first, isNot(contains('password')));
      expect(first, isNot(contains('secret')));
      expect(
        trackerOAuthOrigin(
          mode: AuthType.basic,
          configuredServer: 'https://example.test:8443/base',
          username: 'reader',
        ),
        isNot(first),
      );
    },
  );
  test(
    'verified UI origin uses stable catalogue and account instead of endpoint',
    () {
      const binding = AccountBinding(
        address: 'http://lan',
        userId: 2,
        username: 'Reader',
        catalogId: 'catalog',
      );
      expect(
        trackerOAuthOrigin(
          mode: AuthType.uiLogin,
          configuredServer: 'https://external',
          username: 'different',
          binding: binding,
        ),
        '["uiLogin","catalog",2]',
      );
      const oldBinding = AccountBinding(
        address: 'http://lan',
        username: ' Reader ',
        catalogId: 'catalog',
      );
      expect(
        trackerOAuthOrigin(
          mode: AuthType.uiLogin,
          configuredServer: null,
          username: null,
          binding: oldBinding,
        ),
        '["uiLogin","catalog","Reader"]',
      );
    },
  );
  test(
    'legacy UI uses configured endpoint and stored username; absent identity refuses',
    () {
      expect(
        trackerOAuthOrigin(
          mode: AuthType.uiLogin,
          configuredServer: 'https://server',
          username: 'Reader',
        ),
        '["uiLogin","https://server","Reader"]',
      );
      expect(
        trackerOAuthOrigin(
          mode: AuthType.uiLogin,
          configuredServer: 'https://server',
          username: null,
        ),
        isNull,
      );
      expect(
        trackerOAuthOrigin(
          mode: AuthType.simpleLogin,
          configuredServer: 'https://server',
          username: '',
        ),
        isNull,
      );
      expect(
        trackerOAuthOrigin(
          mode: AuthType.none,
          configuredServer: 'https://server',
          username: null,
        ),
        '["none","https://server",null]',
      );
    },
  );
}
