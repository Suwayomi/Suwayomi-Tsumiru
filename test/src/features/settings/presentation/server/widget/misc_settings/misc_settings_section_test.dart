import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/misc_settings/graphql/__generated__/misc_logs.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/misc_settings/misc_settings_section.dart';
import 'package:tsumiru/src/features/settings/search/settings_search_registry.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _LogsLink extends Link {
  _LogsLink(this.state);

  Fragment$MiscLogsSettingsDto state;
  int queries = 0;
  int mutations = 0;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    if (name == 'MiscLogsSettings') {
      queries++;
      yield Response(
        response: {},
        data: {'__typename': 'Query', 'settings': state.toJson()},
      );
      return;
    }
    if (name == 'SetMiscLogsSettings') {
      mutations++;
      final patch =
          request.variables['settings'] as Map<String, dynamic>? ?? const {};
      state = Fragment$MiscLogsSettingsDto(
        maxLogFiles: state.maxLogFiles,
        maxLogFileSize:
            (patch['maxLogFileSize'] as String?) ?? state.maxLogFileSize,
        maxLogFolderSize: state.maxLogFolderSize,
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

void main() {
  testWidgets('misc rows expose separate semantics nodes', (tester) async {
    final link = _LogsLink(
      Fragment$MiscLogsSettingsDto(
        maxLogFiles: 31,
        maxLogFileSize: '10mb',
        maxLogFolderSize: '100mb',
      ),
    );
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
            body: SingleChildScrollView(
              child: MiscSettingsSection(
                miscSettingsDto: Fragment$MiscSettingsDto(
                  debugLogsEnabled: false,
                  systemTrayEnabled: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(
      find.bySemanticsLabel(RegExp('Log file cleanup')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Debug logs')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Maximum log file size')),
      findsOneWidget,
    );

    final cleanup = tester.getSemantics(find.text('Log file cleanup'));
    expect(cleanup.label, isNot(contains('Debug logs')));
    expect(cleanup.label, isNot(contains('Maximum log file size')));

    // The web engine folds a tappable row into its neighbouring switch rows
    // unless the row carries its own boundary (same guard as the OPDS and
    // WebView rows). Pin the boundary on every tappable Misc row.
    for (final label in const [
      'Log file cleanup',
      'Maximum log file size',
      'Maximum size of all log files',
    ]) {
      final target = tester.widget<SettingsHighlightTarget>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(SettingsHighlightTarget),
        ),
      );
      final child = target.child;
      expect(
        child is Semantics &&
            child.container &&
            child.explicitChildNodes,
        isTrue,
        reason: '$label row is missing its Semantics merge guard',
      );
    }
  });

  testWidgets('an invalid log size is rejected and never sent', (tester) async {
    final link = _LogsLink(
      Fragment$MiscLogsSettingsDto(
        maxLogFiles: 7,
        maxLogFileSize: '1MB',
        maxLogFolderSize: '10MB',
      ),
    );
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
            body: SingleChildScrollView(
              child: MiscSettingsSection(
                miscSettingsDto: Fragment$MiscSettingsDto(
                  debugLogsEnabled: false,
                  systemTrayEnabled: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Maximum log file size'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), '5TB');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(link.mutations, 0);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), '5MB');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(link.mutations, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('5MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
