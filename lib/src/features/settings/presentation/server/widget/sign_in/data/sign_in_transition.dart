import '../../../../../../../constants/enum.dart';

enum SignInFollowUp {
  keepSession,
  none,
  basic,
  simple,
  ui,
  retryAdmin,
  reauthenticate,
}

enum SignInRefusal {
  credentialsRequired,
  adminOnly,
  unsupportedWebMode,
  webCredentials,
  separateSaves,
}

class SignInDiff {
  const SignInDiff({
    this.username = false,
    this.password = false,
    this.audience = false,
    this.accessExpiry = false,
    this.refreshExpiry = false,
  });

  final bool username;
  final bool password;
  final bool audience;
  final bool accessExpiry;
  final bool refreshExpiry;
  bool get credentials => username || password;
}

class SignInDecision {
  const SignInDecision.follow(this.followUp) : refusal = null;
  const SignInDecision.refuse(this.refusal) : followUp = null;

  final SignInFollowUp? followUp;
  final SignInRefusal? refusal;
}

SignInDecision decideSignInTransition({
  required bool accounts,
  required AuthType currentMode,
  required AuthType finalMode,
  required SignInDiff diff,
  required bool admin,
  required bool web,
  required bool hasCredentials,
}) {
  if (accounts && !admin && diff.credentials) {
    return const SignInDecision.refuse(SignInRefusal.adminOnly);
  }
  final entering = currentMode != finalMode;
  if (web &&
      (finalMode == AuthType.basic || finalMode == AuthType.simpleLogin)) {
    if (entering) {
      return const SignInDecision.refuse(SignInRefusal.unsupportedWebMode);
    }
    if (finalMode == AuthType.basic && diff.credentials || diff.username) {
      return const SignInDecision.refuse(SignInRefusal.webCredentials);
    }
  }
  if (accounts &&
      !admin &&
      (finalMode == AuthType.basic || finalMode == AuthType.simpleLogin) &&
      (entering || diff.credentials)) {
    return const SignInDecision.refuse(SignInRefusal.adminOnly);
  }
  if (finalMode != AuthType.none &&
      (entering || diff.credentials) &&
      !hasCredentials) {
    return const SignInDecision.refuse(SignInRefusal.credentialsRequired);
  }
  if (accounts &&
      finalMode == AuthType.uiLogin &&
      entering &&
      diff.credentials) {
    return const SignInDecision.refuse(SignInRefusal.separateSaves);
  }
  if (finalMode == AuthType.uiLogin && diff.audience) {
    return const SignInDecision.follow(SignInFollowUp.reauthenticate);
  }
  if (finalMode == AuthType.none) {
    return SignInDecision.follow(
      entering ? SignInFollowUp.none : SignInFollowUp.keepSession,
    );
  }
  if (finalMode == AuthType.basic && (entering || diff.credentials)) {
    return const SignInDecision.follow(SignInFollowUp.basic);
  }
  if (finalMode == AuthType.simpleLogin && (entering || diff.username)) {
    return const SignInDecision.follow(SignInFollowUp.simple);
  }
  if (finalMode == AuthType.uiLogin && entering) {
    return SignInDecision.follow(
      accounts ? SignInFollowUp.retryAdmin : SignInFollowUp.ui,
    );
  }
  return const SignInDecision.follow(SignInFollowUp.keepSession);
}
