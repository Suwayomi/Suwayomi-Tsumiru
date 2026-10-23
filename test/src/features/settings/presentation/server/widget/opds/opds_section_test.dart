import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/opds/graphql/__generated__/opds.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/opds/opds_section.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/compact_switch.dart';

class _UndefinedOpdsLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    if (name == 'OpdsLegacySettings') {
      yield Response(
        response: {},
        errors: [
          const GraphQLError(
            message:
                "Validation error (FieldUndefined@[settings/opdsUseBinaryFileSizes]) : Field 'opdsUseBinaryFileSizes' in type 'SettingsType' is undefined",
          ),
        ],
      );
      return;
    }
    throw StateError('Unexpected operation $name');
  }
}

void main() {
  testWidgets('OPDS section is hidden when the server predates OPDS', (
    tester,
  ) async {
    final client = GraphQLClient(
      link: _UndefinedOpdsLink(),
      cache: GraphQLCache(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          graphQlClientProvider.overrideWithValue(client),
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: AccountCapability.unsupported),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: OpdsSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('OPDS'), findsNothing);
  });

  testWidgets('legacy write re-reads so the switch shows the new value', (
    tester,
  ) async {
    final link = _LegacyOpdsLink(_opdsState(binary: false));
    final client = GraphQLClient(link: link, cache: GraphQLCache());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          graphQlClientProvider.overrideWithValue(client),
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: AccountCapability.unsupported),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: const SingleChildScrollView(child: OpdsSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Binary file size sits in the third card now; target it by label.
    final binarySwitch = find.widgetWithText(
      CompactSwitchListTile,
      'Binary file size',
    );
    expect(binarySwitch, findsOneWidget);
    expect(tester.widget<CompactSwitchListTile>(binarySwitch).value, isFalse);
    final queriesBefore = link.legacyQueries;

    await tester.scrollUntilVisible(
      binarySwitch,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(binarySwitch);
    await tester.pumpAndSettle();

    expect(link.mutations, 1);
    expect(link.state.opdsUseBinaryFileSizes, isTrue);
    expect(link.legacyQueries, greaterThan(queriesBefore));
    expect(tester.widget<CompactSwitchListTile>(binarySwitch).value, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Fragment$OpdsSettingsDto _opdsState({required bool binary}) =>
    Fragment$OpdsSettingsDto(
      opdsUseBinaryFileSizes: binary,
      opdsItemsPerPage: 100,
      opdsEnablePageReadProgress: false,
      opdsMarkAsReadOnDownload: false,
      opdsShowOnlyUnreadChapters: false,
      opdsShowOnlyDownloadedChapters: false,
      opdsSkipChapterMetadataFeed: false,
      opdsChapterSortOrder: Enum$SortOrder.ASC,
      opdsCbzMimetype: Enum$CbzMediaType.LEGACY,
    );

class _LegacyOpdsLink extends Link {
  _LegacyOpdsLink(this.state);

  Fragment$OpdsSettingsDto state;
  int legacyQueries = 0;
  int mutations = 0;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    if (name == 'OpdsLegacySettings') {
      legacyQueries++;
      yield Response(
        response: {},
        data: {'__typename': 'Query', 'settings': state.toJson()},
      );
      return;
    }
    if (name == 'UpdateOpdsUseBinaryFileSizes') {
      mutations++;
      state = _opdsState(
        binary: request.variables['opdsUseBinaryFileSizes'] as bool,
      );
      yield Response(
        response: {},
        data: {
          '__typename': 'Mutation',
          'setSettings': {
            '__typename': 'SetSettingsPayload',
            'settings': state.toJson(),
          },
        },
      );
      return;
    }
    throw StateError('Unexpected operation $name');
  }
}
