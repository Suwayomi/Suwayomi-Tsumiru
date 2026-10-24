import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_executor.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_transition.dart';

const old = SignInValues(
  mode: AuthType.basic,
  username: ' old ',
  password: ' old password ',
  audience: 'server',
  accessExpiry: 'PT5M',
  refreshExpiry: 'PT1440H',
);

void main() {
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
  test(
    'timeout queries effective settings before verification or commit',
    () async {
      final events = <String>[];
      final proposed = old.copyWith(mode: AuthType.simpleLogin);
      await SignInExecutor(
        write: () async {
          events.add('write');
          throw TimeoutException('reply');
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
  for (final accounts in [false, true]) {
    for (final admin in [false, true]) {
      test(
        'audience timeout with ended session clears tokens ($accounts, $admin)',
        () async {
          final before = old.copyWith(mode: AuthType.uiLogin);
          final proposed = before.copyWith(audience: 'new');
          final events = <String>[];
          await SignInExecutor(
            write: () async => throw TimeoutException('reply'),
            read: () async {
              events.add('read');
              throw const SignInSessionEnded();
            },
            authenticate: (_, _) async => fail('Audience ends session'),
            commit: (_) async => fail('Do not commit credentials'),
            invalidateUi: () async {
              events.add('drop tokens and socket');
            },
            requestSignIn: (mode) {
              expect(mode, AuthType.uiLogin);
              events.add('form');
            },
          ).run(
            before: before,
            proposed: proposed,
            decide: (effective) => decideSignInTransition(
              accounts: accounts,
              currentMode: before.mode,
              finalMode: effective.mode,
              diff: effective.difference(before),
              admin: admin,
              web: false,
              hasCredentials: true,
            ),
          );
          expect(events, ['read', 'drop tokens and socket', 'form']);
        },
      );
    }
  }
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
        write: () async => throw StateError('server rejected'),
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
      throwsStateError,
    );
  });
}
