// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_repository/extension_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/extension/extension_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/widgets/extension_list_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../../../helpers/fake_extension_repository.dart';

const _name = 'A Rather Long Extension Name';

Extension _extension({bool hasUpdate = false}) => Extension(
      hasUpdate: hasUpdate,
      iconUrl: '',
      isInstalled: true,
      contentWarning: Enum$ContentWarning.SAFE,
      isObsolete: false,
      lang: 'en',
      name: _name,
      pkgName: 'com.example.ext',
      // ignore: deprecated_member_use_from_same_package
      versionCode: 1,
      versionName: '1.4.2',
    );

/// The real tile's leading image talks to the server; this is its stand-in.
Future<void> _pumpTile(
  WidgetTester tester,
  ProviderContainer container, {
  bool hasUpdate = false,
}) async {
  final running = ValueNotifier<String?>(null);
  addTearDown(running.dispose);
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => ValueListenableBuilder<String?>(
            valueListenable: running,
            builder: (context, _, _) => ListTile(
              leading: const SizedBox.square(dimension: 48),
              title: const Text(_name, overflow: TextOverflow.ellipsis),
              subtitle: const Text('English 1.4.2'),
              trailing: ExtensionListTileTailing(
                extension: _extension(hasUpdate: hasUpdate),
                runningAction: running,
                ref: ref,
              ),
            ),
          ),
        ),
      ),
    ),
  ));
}

/// Holds the uninstall open so a test can look at the tile mid-reinstall.
class _PausedExtensionRepository extends FakeExtensionRepository {
  final gate = Completer<void>();

  @override
  Future<void> uninstallExtension(String pkgName) async {
    await gate.future;
    return super.uninstallExtension(pkgName);
  }
}

const _reinstalled = <String>[
  'uninstall com.example.ext',
  'install com.example.ext',
];

void main() {
  late FakeExtensionRepository extensions;
  late ProviderContainer container;

  setUp(() async {
    extensions = FakeExtensionRepository();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    container = ProviderContainer(overrides: [
      extensionRepositoryProvider.overrideWithValue(extensions),
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
    ]);
  });

  tearDown(() => container.dispose());

  testWidgets('an installed extension can be reinstalled in one tap',
      (tester) async {
    await _pumpTile(tester, container);

    await tester.tap(find.byTooltip('Reinstall'));
    await tester.pump();

    expect(extensions.calls, _reinstalled);
  });

  testWidgets('the button says what is happening while it runs',
      (tester) async {
    final paused = _PausedExtensionRepository();
    final pausedContainer = ProviderContainer(overrides: [
      extensionRepositoryProvider.overrideWithValue(paused),
      sharedPreferencesProvider
          .overrideWithValue(await SharedPreferences.getInstance()),
    ]);
    addTearDown(pausedContainer.dispose);
    await _pumpTile(tester, pausedContainer);
    expect(find.text('Uninstall'), findsOneWidget);

    await tester.tap(find.byTooltip('Reinstall'));
    await tester.pump();

    expect(find.text('Reinstalling'), findsOneWidget);

    paused.gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('an extension with an update pending can still be reinstalled',
      (tester) async {
    await _pumpTile(tester, container, hasUpdate: true);
    expect(find.text('Update'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reinstall'));
    await tester.pumpAndSettle();

    expect(extensions.calls, _reinstalled);
  });

  testWidgets('an update pending never hides uninstall', (tester) async {
    await _pumpTile(tester, container, hasUpdate: true);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uninstall'));
    await tester.pumpAndSettle();

    expect(extensions.calls, <String>['uninstall com.example.ext']);
  });

  testWidgets('the actions never crowd the extension name off a phone',
      (tester) async {
    for (final hasUpdate in [false, true]) {
      await _pumpTile(tester, container, hasUpdate: hasUpdate);

      expect(tester.takeException(), isNull, reason: 'hasUpdate: $hasUpdate');
      // Measured at 360dp: a third control squeezes the name to one letter.
      final actions = tester.widget<Row>(find
          .descendant(
              of: find.byType(ExtensionListTileTailing),
              matching: find.byType(Row))
          .first);
      expect(actions.children.length, lessThanOrEqualTo(2),
          reason: 'hasUpdate: $hasUpdate');
    }
  });
}
