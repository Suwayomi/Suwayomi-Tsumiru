import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/presentation/offline_server_mismatch_banner.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';

class _RefusedControl extends BackgroundDownloadController {
  _RefusedControl(super.ref)
    : super(isAndroid: () => false, connectivityChanges: const Stream.empty());
  @override
  Future<T> withOwnership<T>(Future<T> Function() action) async =>
      throw StateError('Downloads did not stop');
}

class _Errors implements Toast {
  final messages = <String>[];
  @override
  void showError(
    String error, {
    bool withMicrotask = false,
    bool instantShow = false,
  }) => messages.add(error);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'refused catalog clear reports failure and retains the mismatch',
    (tester) async {
      final errors = _Errors();
      var loads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            offlineEnabledProvider.overrideWithValue(true),
            backgroundDownloadControllerProvider.overrideWith(
              _RefusedControl.new,
            ),
            toastProvider.overrideWith((_) => errors),
            offlineServerMismatchProvider.overrideWith((_) async {
              loads++;
              return const OfflineServerMismatch(
                catalogServer: 'A',
                currentServer: 'B',
                dismissed: false,
              );
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: OfflineServerMismatchBanner()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(OfflineServerMismatchBanner)),
      )!;
      await tester.tap(
        find.widgetWithText(TextButton, l10n.offlineServerMismatchClear),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          l10n.offlineServerMismatchClearAction,
        ),
      );
      await tester.pumpAndSettle();
      expect(errors.messages, [l10n.offlineCatalogClearFailed]);
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(loads, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
