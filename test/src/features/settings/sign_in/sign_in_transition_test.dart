import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_transition.dart';

void main() {
  const modes = AuthType.values;
  const entering = {
    AuthType.none: SignInFollowUp.none,
    AuthType.basic: SignInFollowUp.basic,
    AuthType.simpleLogin: SignInFollowUp.simple,
    AuthType.uiLogin: SignInFollowUp.ui,
  };
  for (final accounts in [false, true]) {
    for (final admin in [false, true]) {
      for (final web in [false, true]) {
        for (final from in modes) {
          for (final to in modes) {
            test('$accounts accounts, $admin admin, $web web: $from → $to', () {
              final result = decideSignInTransition(
                accounts: accounts,
                currentMode: from,
                finalMode: to,
                diff: const SignInDiff(),
                admin: admin,
                web: web,
                hasCredentials: true,
              );
              final unsupported =
                  to == AuthType.basic || to == AuthType.simpleLogin;
              if (from != to && unsupported && web) {
                expect(result.refusal, SignInRefusal.unsupportedWebMode);
              } else if (from != to && unsupported && accounts && !admin) {
                expect(result.refusal, SignInRefusal.adminOnly);
              } else {
                expect(result.refusal, isNull);
                expect(
                  result.followUp,
                  from == to
                      ? SignInFollowUp.keepSession
                      : accounts && to == AuthType.uiLogin
                      ? SignInFollowUp.retryAdmin
                      : entering[to],
                );
              }
            });
          }
        }
        for (final mode in modes) {
          for (final change in [
            (
              name: 'username',
              diff: const SignInDiff(username: true),
              follow: mode == AuthType.basic
                  ? SignInFollowUp.basic
                  : mode == AuthType.simpleLogin
                  ? SignInFollowUp.simple
                  : SignInFollowUp.keepSession,
            ),
            (
              name: 'password',
              diff: const SignInDiff(password: true),
              follow: mode == AuthType.basic
                  ? SignInFollowUp.basic
                  : SignInFollowUp.keepSession,
            ),
            (
              name: 'expiry',
              diff: const SignInDiff(accessExpiry: true, refreshExpiry: true),
              follow: SignInFollowUp.keepSession,
            ),
            (
              name: 'audience',
              diff: const SignInDiff(audience: true),
              follow: mode == AuthType.uiLogin
                  ? SignInFollowUp.reauthenticate
                  : SignInFollowUp.keepSession,
            ),
            (
              name: 'password and audience',
              diff: const SignInDiff(password: true, audience: true),
              follow: mode == AuthType.uiLogin
                  ? SignInFollowUp.reauthenticate
                  : mode == AuthType.basic
                  ? SignInFollowUp.basic
                  : SignInFollowUp.keepSession,
            ),
          ]) {
            test(
              '$accounts accounts, $admin admin, $web web: $mode ${change.name}',
              () {
                final result = decideSignInTransition(
                  accounts: accounts,
                  currentMode: mode,
                  finalMode: mode,
                  diff: change.diff,
                  admin: admin,
                  web: web,
                  hasCredentials: true,
                );
                if (accounts && !admin && change.diff.credentials) {
                  expect(result.refusal, SignInRefusal.adminOnly);
                } else if (web &&
                    (change.diff.credentials && mode == AuthType.basic ||
                        change.diff.username && mode == AuthType.simpleLogin)) {
                  expect(result.refusal, SignInRefusal.webCredentials);
                } else {
                  expect(result.followUp, change.follow);
                }
              },
            );
          }
        }
        test('None always available ($accounts, $admin, $web)', () {
          final result = decideSignInTransition(
            accounts: accounts,
            currentMode: AuthType.uiLogin,
            finalMode: AuthType.none,
            diff: const SignInDiff(),
            admin: admin,
            web: web,
            hasCredentials: false,
          );
          expect(result.followUp, SignInFollowUp.none);
        });
      }
    }
  }
  for (final from in modes) {
    for (final to in modes.where(
      (mode) => mode != from && mode != AuthType.none,
    )) {
      test('combined credential and mode save $from → $to', () {
        final stable = decideSignInTransition(
          accounts: false,
          currentMode: from,
          finalMode: to,
          diff: const SignInDiff(username: true, password: true),
          admin: true,
          web: false,
          hasCredentials: true,
        );
        expect(stable.followUp, entering[to]);
        final preview = decideSignInTransition(
          accounts: true,
          currentMode: from,
          finalMode: to,
          diff: const SignInDiff(username: true, password: true),
          admin: true,
          web: false,
          hasCredentials: true,
        );
        if (to == AuthType.uiLogin) {
          expect(preview.refusal, SignInRefusal.separateSaves);
        } else {
          expect(preview.followUp, entering[to]);
        }
        final blank = decideSignInTransition(
          accounts: false,
          currentMode: from,
          finalMode: to,
          diff: const SignInDiff(),
          admin: true,
          web: false,
          hasCredentials: false,
        );
        expect(blank.refusal, SignInRefusal.credentialsRequired);
      });
    }
  }
}
