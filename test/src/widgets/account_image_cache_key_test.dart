import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/domain/account_binding.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/widgets/cover_cache/cover_cache.dart';

class _Store extends AuthCredentialsStore {
  int epoch = 0;
  bool changing = false;
  @override
  int get sessionEpoch => epoch;
  @override
  bool get sessionChanging => changing;
}

AuthCredentialsState _credentials(String account, String token) =>
    AuthCredentialsState(
      accountBinding: AccountBinding(
        address: 'http://server',
        username: account,
        catalogId: account,
        userId: 1,
      ),
      uiAccessToken: token,
    );

void main() {
  const url = 'http://server/api/v1/manga/1/thumbnail';
  test(
    'same URL separates accounts and returns to stable A key after restart',
    () {
      final store = _Store();
      String key(String account, AuthCredentialsStore owner) =>
          accountImageCacheKey(
            url,
            authType: AuthType.uiLogin,
            store: owner,
            credentials: _credentials(account, 'token'),
          );
      expect(key('a', store), isNot(key('b', store)));
      expect(key('a', store), key('a', _Store()));
    },
  );

  test(
    'token rotation does not change the account cache key or include credentials',
    () {
      final store = _Store();
      final first = accountImageCacheKey(
        '$url?token=secret-one',
        authType: AuthType.uiLogin,
        store: store,
        credentials: _credentials('a', 'secret-one'),
      );
      final second = accountImageCacheKey(
        '$url?token=secret-two',
        authType: AuthType.uiLogin,
        store: store,
        credentials: _credentials('a', 'secret-two'),
      );
      expect(first, second);
      expect(
        first,
        accountImageCacheKey(
          url,
          authType: AuthType.uiLogin,
          store: store,
          credentials: _credentials('a', 'secret-two'),
        ),
      );
      expect(first, isNot(contains('secret')));
      expect(first, isNot(contains('token=')));
    },
  );

  test(
    'unbound and changing sessions cannot reuse account or previous session keys',
    () {
      final store = _Store();
      String key(AuthCredentialsState? credentials) => accountImageCacheKey(
        url,
        authType: AuthType.uiLogin,
        store: store,
        credentials: credentials,
      );
      final bound = key(_credentials('a', 'secret'));
      final unbound = key(null);
      store.epoch++;
      expect(key(null), isNot(unbound));
      store.changing = true;
      expect(key(_credentials('a', 'secret')), isNot(bound));
      expect(
        accountImageCacheKey(
          url,
          authType: AuthType.uiLogin,
          store: _Store(),
          credentials: null,
        ),
        isNot(unbound),
      );
    },
  );

  test('legacy auth preserves existing URL keys', () {
    for (final mode in AuthType.values.where(
      (mode) => mode != AuthType.uiLogin,
    )) {
      expect(
        accountImageCacheKey(
          url,
          authType: mode,
          store: _Store(),
          credentials: null,
        ),
        url,
      );
    }
  });
}
