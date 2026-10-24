import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_executor.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_transition.dart';

void main() {
  test('masked or unconfirmed settings never change the sign-in', () async {
    const before = SignInValues(
      mode: AuthType.uiLogin,
      username: 'admin',
      password: 'secret',
      audience: 'server',
      accessExpiry: 'PT5M',
      refreshExpiry: 'PT1440H',
    );
    final proposed = before.copyWith(accessExpiry: 'PT10M');
    for (final reply in [
      proposed.copyWith(mode: AuthType.none, username: ''),
      proposed.copyWith(username: 'other'),
      before,
    ]) {
      final executor = SignInExecutor(
        write: () async => reply,
        read: () async => fail('No fallback for unconfirmed replies'),
        authenticate: (_, _) async => fail('Must retain credentials'),
        commit: (_) async => fail('Must retain mode'),
        requestSignIn: (_) => fail('Must retain the current sign-in'),
      );
      await expectLater(
        executor.run(
          before: before,
          proposed: proposed,
          decide: (_) => const SignInDecision.follow(SignInFollowUp.none),
        ),
        throwsStateError,
      );
    }
  });

  test(
    'verification failure preserves credentials and success commits them',
    () async {
      const before = SignInValues(
        mode: AuthType.basic,
        username: 'admin',
        password: 'old password',
        audience: 'server',
        accessExpiry: 'PT5M',
        refreshExpiry: 'PT1440H',
      );
      final proposed = before.copyWith(
        mode: AuthType.uiLogin,
        password: 'new password',
      );
      var stored = before;
      var verificationWorks = false;
      AuthType? requested;
      final events = <String>[];
      final executor = SignInExecutor(
        write: () async => proposed,
        read: () async => throw StateError('unexpected query'),
        authenticate: (_, effective) async {
          events.add('verify');
          expect(stored, same(before));
          expect(effective.password, 'new password');
          if (!verificationWorks) throw StateError('rejected');
        },
        commit: (mode) async {
          events.add('commit');
          stored = proposed.copyWith(mode: mode);
        },
        requestSignIn: (mode) => requested = mode,
      );
      Future<void> save() => executor.run(
        before: before,
        proposed: proposed,
        decide: (_) => const SignInDecision.follow(SignInFollowUp.ui),
      );
      await expectLater(save(), throwsStateError);
      expect(stored, same(before));
      expect(requested, AuthType.uiLogin);
      expect(events, ['verify']);

      verificationWorks = true;
      events.clear();
      await save();
      expect(stored.mode, AuthType.uiLogin);
      expect(stored.password, 'new password');
      expect(events, ['verify', 'commit']);
    },
  );
}
