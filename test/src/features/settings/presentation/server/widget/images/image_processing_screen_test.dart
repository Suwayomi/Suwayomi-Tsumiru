// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/data/user_settings.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/data/images_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/image_conversions.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/image_processing_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

/// Fake serve repository that stores the written map, standing in for the
/// server: the editor test reads it back through the provider override.
class _FakeServeRepository extends ServeConversionsRepository {
  _FakeServeRepository({required this.onWrite})
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost/'),
          cache: GraphQLCache(),
        ),
        routing: UserSettingsRouting(
          account: AccountRepository(
            GraphQLClient(
              link: HttpLink('http://localhost/'),
              cache: GraphQLCache(),
            ),
          ),
          access: () =>
              AccountAccess(capability: AccountCapability.unsupported),
          settings: () async => null,
          updated: () {},
        ),
      );

  final void Function(
    List<Input$SettingsDownloadConversionTypeInput> inputs,
  )
  onWrite;

  @override
  Future<void> write(
    List<Input$SettingsDownloadConversionTypeInput> conversions,
  ) async {
    onWrite(conversions);
  }
}

Future<void> _pumpEditor(
  WidgetTester tester,
  List<ServerConversion> Function() readStored,
  void Function(List<Input$SettingsDownloadConversionTypeInput> inputs)
  onWrite,
) async {
  final client = GraphQLClient(
    link: HttpLink('http://localhost/'),
    cache: GraphQLCache(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        graphQlClientProvider.overrideWithValue(client),
        settledAccountAccessProvider.overrideWithValue(
          AccountAccess(capability: AccountCapability.unsupported),
        ),
        personalSettingsStateProvider.overrideWithValue(
          PersonalSettingsState.ready,
        ),
        serveConversionsProvider.overrideWith((ref) async => readStored()),
        serveConversionsRepositoryProvider.overrideWithValue(
          _FakeServeRepository(onWrite: onWrite),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ImageProcessingScreen(kind: ImageProcessingKind.serve),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Compression fields of every rule card, including ones scrolled out of
/// view below the fold.
Finder _compressionFields(WidgetTester tester) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText == 'Compression level',
  skipOffstage: false,
);

/// The jpeg rule's compression field (the last card; the first is the blank
/// `default` rule, which Save drops because its target is empty).
Future<void> _editRuleCompression(
  WidgetTester tester,
  String text,
) async {
  final field = _compressionFields(tester).last;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pump();
}

Finder get _saveFinder =>
    find.widgetWithText(FilledButton, 'Save', skipOffstage: false);

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_saveFinder).onPressed != null;

Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(_saveFinder);
  await tester.pumpAndSettle();
  await tester.tap(_saveFinder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('save shows the stored value and disables Save afterwards', (
    tester,
  ) async {
    var stored = [
      ServerConversion(mimeType: 'image/jpeg', target: 'image/webp'),
    ];
    await _pumpEditor(tester, () => stored, (inputs) {
      stored = inputs
          .map(
            (i) => ServerConversion(
              mimeType: i.mimeType,
              target: i.target,
              compressionLevel: i.compressionLevel,
              callTimeout: i.callTimeout,
              connectTimeout: i.connectTimeout,
            ),
          )
          .toList();
    });
    expect(tester.takeException(), isNull);
    expect(_saveEnabled(tester), isFalse);

    await _editRuleCompression(tester, '0.5');
    expect(_saveEnabled(tester), isTrue);

    await _tapSave(tester);
    expect(tester.takeException(), isNull);

    // The editor shows exactly what the fake server now holds, and with no
    // pending edits Save is disabled again.
    expect(
      tester.widget<TextField>(_compressionFields(tester).last).controller?.text,
      '0.5',
    );
    expect(stored.single.compressionLevel, 0.5);
    expect(_saveEnabled(tester), isFalse);
  });

  testWidgets('unparsable compression text shows Invalid input', (
    tester,
  ) async {
    final stored = [
      ServerConversion(mimeType: 'image/jpeg', target: 'image/webp'),
    ];
    await _pumpEditor(tester, () => stored, (_) {});
    expect(tester.takeException(), isNull);

    await _editRuleCompression(tester, 'abc');
    expect(find.text('Invalid input', skipOffstage: false), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);
  });

  testWidgets(
    'invalid compression does not block Save after switching to Disabled',
    (tester) async {
      final stored = [
        ServerConversion(mimeType: 'image/jpeg', target: 'image/webp'),
      ];
      await _pumpEditor(tester, () => stored, (_) {});
      expect(tester.takeException(), isNull);

      await _editRuleCompression(tester, 'abc');
      expect(_saveEnabled(tester), isFalse);

      // Switch the jpeg rule (last card) to Disabled; its hidden compression
      // text must no longer block Save.
      final modeTile = find.byType(ListTile, skipOffstage: false).last;
      await tester.ensureVisible(modeTile);
      await tester.pumpAndSettle();
      await tester.tap(modeTile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
        find.text('Invalid input', skipOffstage: false),
        findsNothing,
      );
      expect(_saveEnabled(tester), isTrue);
    },
  );

  testWidgets('duplicate query params open the search editor as Invalid input', (
    tester,
  ) async {
    final stored = [
      ServerConversion(
        mimeType: 'image/jpeg',
        target: 'https://example.com/convert?a=1&a=2',
      ),
    ];
    await _pumpEditor(tester, () => stored, (_) {});
    expect(tester.takeException(), isNull);

    final paramsButton = find.widgetWithText(
      OutlinedButton,
      'Search parameters (2)',
      skipOffstage: false,
    );
    await tester.ensureVisible(paramsButton);
    await tester.pumpAndSettle();
    await tester.tap(paramsButton);
    await tester.pumpAndSettle();

    // Re-enter the same target so ids are re-retained through _setTarget:
    // each `a` occurrence must keep its own id instead of sharing one.
    final targetField = find
        .byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'MIME-Type target',
          skipOffstage: false,
        )
        .last;
    await tester.ensureVisible(targetField);
    await tester.pumpAndSettle();
    await tester.enterText(
      targetField,
      'https://example.com/convert?a=1&a=2',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(find.text('Invalid input', skipOffstage: false), findsOneWidget);
  });
}
