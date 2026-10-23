import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/opds/opds_section.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

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
}
