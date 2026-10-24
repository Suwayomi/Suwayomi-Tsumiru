import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/database/data/database_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/database/database_section.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/database/graphql/__generated__/database.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/input_popup/domain/settings_prop_type.dart';
import 'package:tsumiru/src/widgets/input_popup/settings_prop_tile.dart';

class _ThrowingLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    throw StateError('Unexpected operation');
  }
}

Fragment$DatabaseSettingsDto _settings(Enum$DatabaseType type) =>
    Fragment$DatabaseSettingsDto(
      databaseType: type,
      databaseUrl: 'postgresql://localhost:5432/suwayomi',
      databaseUsername: 'suwayomi',
      databasePassword: 'secret',
      useHikariConnectionPool: false,
    );

Future<ProviderContainer> _pumpSection(
  WidgetTester tester,
  Enum$DatabaseType Function() readType,
) async {
  final client = GraphQLClient(link: _ThrowingLink(), cache: GraphQLCache());
  final container = ProviderContainer(
    overrides: [
      graphQlClientProvider.overrideWithValue(client),
      settledAccountAccessProvider.overrideWithValue(
        AccountAccess(capability: AccountCapability.unsupported),
      ),
      previewDatabaseSettingsProvider.overrideWith((ref) async => null),
      databaseSettingsProvider.overrideWith(
        (ref) async => _settings(readType()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DatabaseSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

List<SettingsPropTile> _textTiles(WidgetTester tester) => tester
    .widgetList<SettingsPropTile>(find.byType(SettingsPropTile))
    .where((tile) => tile.type is TextFieldProp)
    .toList();

bool _textEnabled(SettingsPropTile tile) {
  final type = tile.type;
  if (type is TextFieldProp) return type.onChanged != null;
  return false;
}

void main() {
  testWidgets('database url, username and password follow the H2 gate', (
    tester,
  ) async {
    var type = Enum$DatabaseType.H2;
    final container = await _pumpSection(tester, () => type);
    expect(tester.takeException(), isNull);

    final h2Tiles = _textTiles(tester);
    expect(h2Tiles, hasLength(3));
    for (final tile in h2Tiles) {
      expect(_textEnabled(tile), isFalse);
    }
    final passwordTile = h2Tiles.singleWhere(
      (tile) => tile.title == 'Password',
    );
    expect(passwordTile.subtitle, isNull);

    type = Enum$DatabaseType.POSTGRESQL;
    container.invalidate(databaseSettingsProvider);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final pgTiles = _textTiles(tester);
    expect(pgTiles, hasLength(3));
    for (final tile in pgTiles) {
      expect(_textEnabled(tile), isTrue);
    }
  });
}
