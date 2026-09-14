import 'package:hooks_riverpod/hooks_riverpod.dart';

abstract interface class AuthSessionTransition {
  Future<T> run<T>(Future<T> Function() action);
}

final authSessionTransitionProvider = Provider<AuthSessionTransition?>(
  (ref) => null,
);
