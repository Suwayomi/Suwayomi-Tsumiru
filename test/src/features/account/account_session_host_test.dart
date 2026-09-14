import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/presentation/account_session_host.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/auth_session_transition.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';

class _DrainTransition implements AuthSessionTransition {
  _DrainTransition(this.runtime);
  final OfflineRuntimeStorage runtime;

  @override
  Future<T> run<T>(Future<T> Function() action) async {
    await runtime.drain();
    return action();
  }
}

class _Auth extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState(uiAccessToken: 'A');

  void publish(String token, {int epoch = 0, bool changing = false}) {
    state = AsyncData(
      AuthCredentialsState(
        uiAccessToken: token,
        sessionEpoch: epoch,
        sessionChanging: changing,
      ),
    );
  }
}

final _accountData = FutureProvider<String>((ref) async => 'A library');

class _View extends ConsumerWidget {
  const _View(this.changing);
  final bool changing;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    home: Offstage(
      offstage: changing,
      child: Text(ref.watch(_accountData).value ?? 'Loading library'),
    ),
  );
}

void main() {
  testWidgets(
    'refused transition retains the usable account while work drains',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          authCredentialsStoreProvider.overrideWith(_Auth.new),
          authSessionTransitionProvider.overrideWith(
            (ref) => _DrainTransition(
              ref.read(offlineRuntimeStorageProvider.notifier),
            ),
          ),
        ],
      );
      await container.read(authCredentialsStoreProvider.future);
      final pending = Completer<void>();
      final runtime = container.read(offlineRuntimeStorageProvider.notifier);
      final tracked = runtime.track(() => pending.future);
      var restarts = 0;
      var resumed = false;
      await tester.pumpWidget(
        AccountSessionHost(
          initialContainer: container,
          sessionKey: (c) =>
              c.read(authCredentialsStoreProvider).value!.uiAccessToken!,
          onRetained: (c) async {
            await runtime.whenIdle();
            resumed = true;
          },
          restart: (old) async {
            restarts++;
            throw StateError('must not retire a refused session');
          },
          builder: _View.new,
          loading: const SizedBox(),
          errorBuilder: (error) => Text('$error'),
        ),
      );
      await tester.pumpAndSettle();
      final auth =
          container.read(authCredentialsStoreProvider.notifier) as _Auth;
      Object? failure;
      final change = auth
          .withIdentityChange(() async {
            auth.publish('B');
          })
          .catchError((Object error) {
            failure = error;
          });
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await change;
      expect(failure, isA<TimeoutException>());
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('A library'), findsOneWidget);
      expect(restarts, 0);
      expect(resumed, isFalse);
      pending.complete();
      await tracked;
      await tester.pumpAndSettle();
      expect(resumed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account switch hides A and B starts without previous data', (
    tester,
  ) async {
    final a = ProviderContainer(
      overrides: [authCredentialsStoreProvider.overrideWith(_Auth.new)],
    );
    final bData = Completer<String>();
    final b = ProviderContainer(
      overrides: [
        authCredentialsStoreProvider.overrideWith(_Auth.new),
        _accountData.overrideWith((ref) => bData.future),
      ],
    );
    await a.read(authCredentialsStoreProvider.future);
    await b.read(authCredentialsStoreProvider.future);
    var restarts = 0;
    await tester.pumpWidget(
      AccountSessionHost(
        initialContainer: a,
        restart: (old) async {
          restarts++;
          return b;
        },
        builder: _View.new,
        loading: const SizedBox(),
        errorBuilder: (error) => Text('$error'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A library'), findsOneWidget);
    final auth = a.read(authCredentialsStoreProvider.notifier) as _Auth;
    auth.publish('A', epoch: 1, changing: true);
    await tester.pump();
    expect(find.text('A library'), findsNothing);
    expect(restarts, 0);
    auth.publish('B', epoch: 2);
    await tester.pumpAndSettle();
    expect(restarts, 1);
    expect(find.text('A library'), findsNothing);
    expect(find.text('Loading library'), findsOneWidget);
    bData.complete('B library');
    await tester.pumpAndSettle();
    expect(find.text('B library'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('token refresh preserves the mounted application session', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [authCredentialsStoreProvider.overrideWith(_Auth.new)],
    );
    await container.read(authCredentialsStoreProvider.future);
    var restarts = 0;
    await tester.pumpWidget(
      AccountSessionHost(
        initialContainer: container,
        restart: (old) async {
          restarts++;
          return old;
        },
        builder: _View.new,
        loading: const SizedBox(),
        errorBuilder: (error) => Text('$error'),
      ),
    );
    await tester.pumpAndSettle();
    (container.read(authCredentialsStoreProvider.notifier) as _Auth).publish(
      'rotated-A',
    );
    await tester.pumpAndSettle();
    expect(restarts, 0);
    expect(find.text('A library'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
