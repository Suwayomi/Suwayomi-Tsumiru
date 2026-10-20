import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_page_store_io.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
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
  test('workers stop before catalog rows and files are cleared', () async {
    final events = <String>[];

    await clearOfflineCatalogWithDependencies(
      stopBackground: () async => events.add('background'),
      stopMainPump: () async => events.add('main'),
      clearDatabase: () async => events.add('database'),
      clearFiles: () async => events.add('files'),
      clearIdentity: () async => events.add('identity'),
      finish: () => events.add('finish'),
    );

    expect(events, [
      'background',
      'main',
      'database',
      'files',
      'identity',
      'finish',
    ]);

    // A refused drain stops the wipe at the first step and still releases
    // the restart suppression.
    final failed = <String>[];
    await expectLater(
      clearOfflineCatalogWithDependencies(
        stopBackground: () async => failed.add('background'),
        stopMainPump: () async => throw StateError('Downloads did not stop'),
        clearDatabase: () async => failed.add('database'),
        clearFiles: () async => failed.add('files'),
        clearIdentity: () async => failed.add('identity'),
        finish: () => failed.add('finish'),
      ),
      throwsStateError,
    );
    expect(failed, ['background', 'finish']);

    // clearAll is one destructive path: pages and covers go, the catalog stays.
    final temp = await Directory.systemTemp.createTemp('tsumiru-offline-');
    addTearDown(() => temp.delete(recursive: true));
    final paths = OfflinePaths(temp.path);
    final store = IoOfflinePageStore(paths);
    final catalog = File('${temp.path}/catalog.sqlite');
    await catalog.writeAsString('catalog');
    await store.writePage(12, 34, 0, [1, 2, 3], 'jpg');
    final cover = File(paths.absolute('covers/12.jpg'));
    await cover.parent.create(recursive: true);
    await cover.writeAsBytes([1]);

    await store.clearAll();

    expect(await catalog.exists(), isTrue);
    expect(await Directory(paths.absolute('12')).exists(), isFalse);
    expect(await Directory(paths.absolute('covers')).exists(), isFalse);
  });

  testWidgets('a failed drain reports the failure and keeps the mismatch', (
    tester,
  ) async {
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
      find.widgetWithText(FilledButton, l10n.offlineServerMismatchClearAction),
    );
    await tester.pumpAndSettle();
    expect(errors.messages, [l10n.offlineCatalogClearFailed]);
    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });
}
