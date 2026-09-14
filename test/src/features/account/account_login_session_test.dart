import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

class _DelayedLogin extends Link {
  final started = Completer<void>();
  final response = Completer<Response>();
  int requests = 0;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    requests++;
    if (requests != 1) throw StateError('Stale login queried account data');
    started.complete();
    yield await response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'server replacement rejects an in-flight login before account lookup',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authCredentialsStoreProvider.future);
      final link = _DelayedLogin();
      final login = container
          .read(authCoordinatorProvider.notifier)
          .loginUi(
            gqlClient: GraphQLClient(link: link, cache: GraphQLCache()),
            username: 'reader',
            password: 'password',
          );
      final rejected = expectLater(login, throwsStateError);
      await link.started.future;
      await container
          .read(authCredentialsStoreProvider.notifier)
          .clearAllForServerSwitch();
      link.response.complete(
        Response(
          response: {},
          data: {
            '__typename': 'Mutation',
            'login': {
              '__typename': 'LoginPayload',
              'accessToken': 'server-a-access',
              'refreshToken': 'server-a-refresh',
            },
          },
        ),
      );
      await rejected;
      expect(link.requests, 1);
      final credentials = container
          .read(authCredentialsStoreProvider)
          .requireValue;
      expect(credentials.uiAccessToken, isNull);
      expect(credentials.accountBinding, isNull);
      expect(credentials.password, isNull);
    },
  );
}
