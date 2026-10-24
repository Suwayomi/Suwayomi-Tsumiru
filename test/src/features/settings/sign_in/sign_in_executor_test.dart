import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_executor.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_transition.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/graphql/__generated__/sign_in.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';

import '../../auth/data/recorded_auth_response.dart';

const old = SignInValues(
  mode: AuthType.basic,
  username: ' old ',
  password: ' old password ',
  audience: 'server',
  accessExpiry: 'PT5M',
  refreshExpiry: 'PT1440H',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final destination in AuthType.values) {
    test(
      'success adopts $destination only after verification and clears obsolete credentials',
      () async {
        final events = <String>[];
        var storedMode = old.mode;
        var oldCredentials = true;
        final proposed = old.copyWith(
          mode: destination,
          password: ' new password ',
        );
        await SignInExecutor(
          write: () async {
            events.add('write');
            return proposed;
          },
          read: () async {
            fail('A successful reply needs no query');
          },
          authenticate: (follow, effective) async {
            events.add('verify');
            expect(storedMode, old.mode);
            expect(oldCredentials, isTrue);
            expect(effective.password, ' new password ');
          },
          commit: (mode) async {
            events.add('commit');
            storedMode = mode;
            oldCredentials = false;
          },
          invalidateUi: () async {
            fail('No audience edit');
          },
          requestSignIn: (_) => fail('Verified'),
        ).run(
          before: old,
          proposed: proposed,
          decide: (effective) => decideSignInTransition(
            accounts: false,
            currentMode: old.mode,
            finalMode: effective.mode,
            diff: effective.difference(old),
            admin: true,
            web: false,
            hasCredentials: true,
          ),
        );
        expect(storedMode, destination);
        expect(oldCredentials, isFalse);
        expect(
          events,
          destination == AuthType.none
              ? ['write', 'commit']
              : ['write', 'verify', 'commit'],
        );
      },
    );
  }
  test(
    'failed verification keeps old credentials and requests the new form',
    () async {
      final proposed = old.copyWith(mode: AuthType.uiLogin);
      AuthType? requested;
      var committed = false;
      final executor = SignInExecutor(
        write: () async => proposed,
        read: () async => throw StateError('unexpected query'),
        authenticate: (_, _) async => throw StateError('rejected'),
        commit: (_) async {
          committed = true;
        },
        invalidateUi: () async {},
        requestSignIn: (mode) => requested = mode,
      );
      await expectLater(
        executor.run(
          before: old,
          proposed: proposed,
          decide: (_) => const SignInDecision.follow(SignInFollowUp.ui),
        ),
        throwsStateError,
      );
      expect(committed, isFalse);
      expect(requested, AuthType.uiLogin);
    },
  );
  for (final failure in [
    TimeoutException('reply'),
    StateError('decode failed'),
    Exception('connection reset'),
  ]) {
    test(
      'uncertain $failure queries effective settings before verification or commit',
      () async {
        final events = <String>[];
        final proposed = old.copyWith(mode: AuthType.simpleLogin);
        await SignInExecutor(
          write: () async {
            events.add('write');
            throw failure;
          },
          read: () async {
            events.add('read');
            return proposed;
          },
          authenticate: (_, _) async {
            events.add('verify');
          },
          commit: (_) async {
            events.add('commit');
          },
          invalidateUi: () async {},
          requestSignIn: (_) => fail('Verified'),
        ).run(
          before: old,
          proposed: proposed,
          decide: (_) => const SignInDecision.follow(SignInFollowUp.simple),
        );
        expect(events, ['write', 'read', 'verify', 'commit']);
      },
    );
  }
  for (final response in [
    (400, 'Token intended for different audience [old]'),
    (200, '{"errors":[{"message":"Unauthorized"}]}'),
  ]) {
    for (final admin in [false, true]) {
      test(
        'audience timeout with ended session clears tokens (${response.$1}, $admin)',
        () async {
          final before = old.copyWith(mode: AuthType.uiLogin);
          final proposed = before.copyWith(audience: 'new');
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
          await container.read(credentialsProvider.future);
          await container.read(customHttpHeadersProvider.future);
          final store = container.read(authCredentialsStoreProvider.notifier);
          await store.saveUiLoginTokens(
            accessToken: 'old',
            refreshToken: 'refresh',
          );
          final http = container.read(graphQlClientProvider);
          final socket = container.read(graphQlSubscriptionClientProvider);
          final events = <String>[];
          await store.withIdentityChange(
            () =>
                SignInExecutor(
                  write: () async => throw TimeoutException('reply'),
                  read: () async {
                    events.add('read');
                    await recordedAuthClient(response.$1, response.$2)
                        .query$ServerSignInStatus(
                          Options$Query$ServerSignInStatus(
                            fetchPolicy: FetchPolicy.noCache,
                          ),
                        )
                        .getData((data) => data.settings);
                    throw StateError('Expected rejection');
                  },
                  authenticate: (_, _) async => fail('Audience ends session'),
                  commit: (_) async => fail('Do not commit credentials'),
                  invalidateUi: () async {
                    await store.clearUiLoginTokens();
                  },
                  requestSignIn: (mode) {
                    expect(mode, AuthType.uiLogin);
                    events.add('form');
                  },
                ).run(
                  before: before,
                  proposed: proposed,
                  decide: (effective) => decideSignInTransition(
                    accounts: true,
                    currentMode: before.mode,
                    finalMode: effective.mode,
                    diff: effective.difference(before),
                    admin: admin,
                    web: false,
                    hasCredentials: true,
                  ),
                ),
          );
          expect(events, ['read', 'form']);
          expect(store.uiLoginTokens(), isNull);
          expect(container.read(graphQlClientProvider), isNot(same(http)));
          expect(
            container.read(graphQlSubscriptionClientProvider),
            isNot(same(socket)),
          );
        },
      );
    }
  }
  test(
    'unknown save and failed re-read offer proposed mode without changing credentials',
    () async {
      AuthType? requested;
      final proposed = old.copyWith(mode: AuthType.uiLogin, audience: 'new');
      await expectLater(
        SignInExecutor(
          write: () async => throw StateError('connection reset'),
          read: () async => throw StateError('server unreachable'),
          authenticate: (_, _) async => fail('Outcome is unknown'),
          commit: (_) async => fail('Keep old credentials'),
          invalidateUi: () async =>
              fail('Do not infer audience rejection from a network failure'),
          requestSignIn: (mode) => requested = mode,
        ).run(
          before: old,
          proposed: proposed,
          decide: (_) => throw StateError('No confirmed settings'),
        ),
        throwsStateError,
      );
      expect(requested, AuthType.uiLogin);
    },
  );
  test('ignored server values use the reply and keep the session', () async {
    final proposed = old.copyWith(mode: AuthType.uiLogin);
    await SignInExecutor(
      write: () async => old,
      read: () async => throw StateError('unexpected query'),
      authenticate: (_, _) async => fail('Server ignored change'),
      commit: (_) async => fail('Server ignored change'),
      invalidateUi: () async => fail('Server ignored change'),
      requestSignIn: (_) => fail('Server ignored change'),
    ).run(
      before: old,
      proposed: proposed,
      decide: (effective) => decideSignInTransition(
        accounts: false,
        currentMode: old.mode,
        finalMode: effective.mode,
        diff: effective.difference(old),
        admin: true,
        web: false,
        hasCredentials: true,
      ),
    );
  });
  test('rejected save never authenticates or changes local state', () async {
    await expectLater(
      SignInExecutor(
        write: () async => throw OperationMessageException(
          OperationException(
            graphqlErrors: const [GraphQLError(message: 'Forbidden')],
          ),
        ),
        read: () async => throw StateError('unexpected query'),
        authenticate: (_, _) async => fail('Server rejected change'),
        commit: (_) async => fail('Server rejected change'),
        invalidateUi: () async => fail('Server rejected change'),
        requestSignIn: (_) => fail('Server rejected change'),
      ).run(
        before: old,
        proposed: old,
        decide: (_) => const SignInDecision.follow(SignInFollowUp.keepSession),
      ),
      throwsA(isA<OperationMessageException>()),
    );
  });
}
