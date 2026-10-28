import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_transition.dart';

void main() {
  test(
    'sign-in transitions choose the required follow-up or refuse unsafe modes',
    () {
      final cases = [
        (
          accounts: false,
          from: AuthType.none,
          to: AuthType.uiLogin,
          diff: const SignInDiff(),
          admin: true,
          web: false,
          follow: SignInFollowUp.ui,
          refusal: null,
        ),
        (
          accounts: false,
          from: AuthType.uiLogin,
          to: AuthType.none,
          diff: const SignInDiff(),
          admin: true,
          web: false,
          follow: SignInFollowUp.none,
          refusal: null,
        ),
        (
          accounts: false,
          from: AuthType.none,
          to: AuthType.uiLogin,
          diff: const SignInDiff(audience: true, password: true),
          admin: true,
          web: false,
          follow: SignInFollowUp.reauthenticate,
          refusal: null,
        ),
        for (final mode in [AuthType.basic, AuthType.simpleLogin]) ...[
          (
            accounts: true,
            from: AuthType.uiLogin,
            to: mode,
            diff: const SignInDiff(),
            admin: false,
            web: false,
            follow: null,
            refusal: SignInRefusal.adminOnly,
          ),
          (
            accounts: false,
            from: AuthType.none,
            to: mode,
            diff: const SignInDiff(),
            admin: true,
            web: true,
            follow: null,
            refusal: SignInRefusal.unsupportedWebMode,
          ),
        ],
      ];
      for (final row in cases) {
        final result = decideSignInTransition(
          accounts: row.accounts,
          currentMode: row.from,
          finalMode: row.to,
          diff: row.diff,
          admin: row.admin,
          web: row.web,
          sameOrigin: false,
          hasCredentials: true,
        );
        expect(result.followUp, row.follow, reason: '$row');
        expect(result.refusal, row.refusal, reason: '$row');
      }
    },
  );
  test('hosted web hands Basic and Simple sign-in to the browser', () {
    for (final mode in [AuthType.basic, AuthType.simpleLogin]) {
      SignInDecision decide({required bool sameOrigin}) =>
          decideSignInTransition(
            accounts: true,
            currentMode: AuthType.none,
            finalMode: mode,
            diff: const SignInDiff(),
            admin: true,
            web: true,
            sameOrigin: sameOrigin,
            hasCredentials: true,
          );

      expect(decide(sameOrigin: true).followUp, SignInFollowUp.reloadBrowser);
      expect(
        decide(sameOrigin: false).refusal,
        SignInRefusal.unsupportedWebMode,
      );
    }
  });
}
