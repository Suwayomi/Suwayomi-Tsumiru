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
import 'package:tsumiru/src/features/browse_center/data/extension_store_repository/extension_store_repository.dart';
import 'package:tsumiru/src/features/browse_center/domain/extension_store/extension_store_model.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension_store/extension_store_screen.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../helpers/legacy_account_access.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _FakeExtensionStoreRepository extends ExtensionStoreRepository {
  _FakeExtensionStoreRepository()
    : failAdd = false,
      super(_dummyClient(), permissions: legacyAccountPermissions);

  final bool failAdd;
  final List<String> added = <String>[];
  final List<String> removed = <String>[];

  @override
  Future<void> addStore(String indexUrl) async {
    if (failAdd) throw Exception('Server error: could not add store');
    added.add(indexUrl);
  }

  @override
  Future<void> removeStore(String indexUrl) async => removed.add(indexUrl);
}

final _storeA = ExtensionStore(
  indexUrl: 'https://a.example/index.pb',
  name: 'Store A',
  contactWebsite: 'https://a.example',
  contactDiscord: 'https://discord.gg/a',
);

ProviderContainer _container({
  required List<ExtensionStore> stores,
  ExtensionStoreRepository? repository,
}) => ProviderContainer(
  overrides: [
    settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
    extensionStoreListProvider.overrideWith(
      (ref) async => (stores: stores, totalCount: stores.length),
    ),
    extensionStoreRepositoryProvider.overrideWithValue(
      repository ?? _FakeExtensionStoreRepository(),
    ),
  ],
);

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ExtensionStoreScreen(),
  ),
);

void main() {
  testWidgets(
    'shows the empty state with a Help button when there are no stores',
    (tester) async {
      final container = _container(stores: []);
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();

      expect(
        find.text("You haven't added an extension store yet"),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Help'), findsOneWidget);
    },
  );

  testWidgets(
    'the FAB opens the add dialog whose Add button is disabled when empty and '
    'when the URL duplicates an existing store',
    (tester) async {
      final container = _container(stores: [_storeA]);
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Store index URL'), findsOneWidget);
      ElevatedButton addButton() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Add'),
      );
      expect(addButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), _storeA.indexUrl);
      await tester.pump();
      expect(find.text('This extension store already exists'), findsOneWidget);
      expect(addButton().onPressed, isNull);

      await tester.enterText(
        find.byType(TextField),
        'https://new.example/index.pb',
      );
      await tester.pump();
      expect(addButton().onPressed, isNotNull);
    },
  );
}
