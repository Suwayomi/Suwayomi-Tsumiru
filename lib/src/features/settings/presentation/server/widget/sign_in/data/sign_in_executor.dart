import 'package:graphql/client.dart';

import '../../../../../../../constants/enum.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import 'sign_in_transition.dart';

class SignInValues {
  const SignInValues({
    required this.mode,
    required this.username,
    required this.password,
    required this.audience,
    required this.accessExpiry,
    required this.refreshExpiry,
  });

  final AuthType mode;
  final String username;
  final String password;
  final String audience;
  final String accessExpiry;
  final String refreshExpiry;

  SignInValues copyWith({
    AuthType? mode,
    String? username,
    String? password,
    String? audience,
    String? accessExpiry,
    String? refreshExpiry,
  }) => SignInValues(
    mode: mode ?? this.mode,
    username: username ?? this.username,
    password: password ?? this.password,
    audience: audience ?? this.audience,
    accessExpiry: accessExpiry ?? this.accessExpiry,
    refreshExpiry: refreshExpiry ?? this.refreshExpiry,
  );

  SignInDiff difference(SignInValues old) => SignInDiff(
    username: username != old.username,
    password: password != old.password,
    audience: audience != old.audience,
    accessExpiry: accessExpiry != old.accessExpiry,
    refreshExpiry: refreshExpiry != old.refreshExpiry,
  );
}

class SignInExecutor {
  const SignInExecutor({
    required this.write,
    required this.read,
    required this.authenticate,
    required this.commit,
    required this.requestSignIn,
  });

  final Future<SignInValues> Function() write;
  final Future<SignInValues> Function() read;
  final Future<void> Function(SignInFollowUp, SignInValues) authenticate;
  final Future<void> Function(AuthType) commit;
  final void Function(AuthType) requestSignIn;

  Future<void> run({
    required SignInValues before,
    required SignInValues proposed,
    required SignInDecision Function(SignInValues) decide,
  }) async {
    late SignInValues effective;
    try {
      effective = await write();
    } catch (error) {
      final cause = error is OperationMessageException
          ? error.exception
          : error;
      if (cause is OperationException &&
          cause.linkException == null &&
          cause.graphqlErrors.isNotEmpty) {
        rethrow;
      }
      try {
        effective = await read();
      } catch (error) {
        if (proposed.mode == AuthType.uiLogin &&
            proposed.audience != before.audience) {
          requestSignIn(AuthType.uiLogin);
          return;
        }
        requestSignIn(proposed.mode);
        rethrow;
      }
    }
    final difference = effective.difference(proposed);
    if (effective.mode != proposed.mode ||
        difference.username ||
        difference.password ||
        difference.audience ||
        difference.accessExpiry ||
        difference.refreshExpiry) {
      throw StateError('The server did not confirm the sign-in settings');
    }
    final decision = decide(effective);
    if (decision.refusal != null) {
      requestSignIn(effective.mode);
      throw StateError('Unsupported effective sign-in transition');
    }
    final followUp = decision.followUp!;
    if (followUp == SignInFollowUp.keepSession) return;
    if (followUp == SignInFollowUp.reauthenticate) {
      requestSignIn(AuthType.uiLogin);
      return;
    }
    try {
      if (followUp != SignInFollowUp.none) {
        await authenticate(followUp, effective);
      }
      await commit(effective.mode);
    } catch (_) {
      requestSignIn(effective.mode);
      rethrow;
    }
  }
}
