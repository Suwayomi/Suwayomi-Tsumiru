import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/graphql/__generated__/web_interface.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/web_interface_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/web_interface/web_interface_section.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../../../helpers/legacy_account_access.dart';

class _Server extends Link {
  final operations = <String>[];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    operations.add(name);
    switch (name) {
      case 'WebInterfaceSettings':
        yield Response(
          response: {},
          errors: [
            const GraphQLError(
              message:
                  'Cannot query field "webUIFlavor" on type "SettingsType".',
            ),
          ],
        );
      case 'InstalledWebInterface':
        yield Response(
          response: {},
          data: {
            '__typename': 'Query',
            'aboutWebUI': {
              '__typename': 'WebUIInfo',
              'tag': 'v1.5.0',
              'channel': 'STABLE',
            },
          },
        );
      case 'WebInterfaceUpdateStatus':
        yield Response(
          response: {},
          data: {
            '__typename': 'Query',
            'getWebUIUpdateStatus': {
              '__typename': 'WebUIUpdateStatus',
              'state': 'IDLE',
              'progress': 0,
              'info': {
                '__typename': 'WebUIInfo',
                'tag': 'v1.5.0',
                'channel': 'STABLE',
              },
            },
          },
        );
      default:
        throw StateError('Unexpected operation: $name');
    }
  }
}

Future<_Server> _pump(
  WidgetTester tester,
  AccountAccess access, {
  Fragment$WebInterfaceSettingsDto? settings,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final server = _Server();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settledAccountAccessProvider.overrideWithValue(access),
        if (settings != null) ...[
          webInterfaceSettingsProvider.overrideWith((ref) async => settings),
          webInterfaceFlavorsProvider.overrideWith(
            (ref) async => [Enum$WebUIFlavor.WEBUI, Enum$WebUIFlavor.TSUMIRU],
          ),
        ],
        graphQlClientProvider.overrideWithValue(
          GraphQLClient(link: server, cache: GraphQLCache()),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: WebInterfaceSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

void main() {
  for (final scenario in [
    (
      flavor: Enum$WebUIFlavor.TSUMIRU,
      channel: Enum$WebUIChannel.STABLE,
      label: 'Stable',
      showsNote: false,
    ),
    (
      flavor: Enum$WebUIFlavor.TSUMIRU,
      channel: Enum$WebUIChannel.BUNDLED,
      label: 'Bundled',
      showsNote: true,
    ),
    (
      flavor: Enum$WebUIFlavor.WEBUI,
      channel: Enum$WebUIChannel.BUNDLED,
      label: 'Bundled',
      showsNote: false,
    ),
  ]) {
    testWidgets(
      '${scenario.flavor.name} ${scenario.channel.name} shows bundled guidance only when applicable in the channel subtitle',
      (tester) async {
        await _pump(
          tester,
          legacyAccountAccess,
          settings: Fragment$WebInterfaceSettingsDto(
            webUIFlavor: scenario.flavor,
            webUIChannel: scenario.channel,
            webUIUpdateCheckInterval: 0,
          ),
        );
        const note =
            'Bundled only works with the default WebUI. Choose Stable or Preview for other interfaces.';
        final channelRow = tester.widget<ListTile>(
          find.ancestor(
            of: find.text('Update channel'),
            matching: find.byType(ListTile),
          ),
        );
        expect(
          find.textContaining(note),
          scenario.showsNote ? findsOneWidget : findsNothing,
        );
        expect(
          find.descendant(
            of: find.byWidget(channelRow.subtitle!),
            matching: find.textContaining(scenario.label),
            matchRoot: true,
          ),
          findsOneWidget,
        );
        if (scenario.showsNote) {
          expect(
            find.descendant(
              of: find.byWidget(channelRow.subtitle!),
              matching: find.textContaining(note),
              matchRoot: true,
            ),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('offers only recognised flavors advertised by the server', () {
    expect(supportedWebInterfaceFlavors(['WEBUI', 'VUI', 'CUSTOM', 'FUTURE']), [
      Enum$WebUIFlavor.WEBUI,
      Enum$WebUIFlavor.VUI,
      Enum$WebUIFlavor.CUSTOM,
    ]);
    expect(supportedWebInterfaceFlavors(['TSUMIRU', 'WEBUI', 'TSUMIRU']), [
      Enum$WebUIFlavor.TSUMIRU,
      Enum$WebUIFlavor.WEBUI,
    ]);
    expect(supportedWebInterfaceFlavors(['FUTURE']), isEmpty);
  });

  test('unknown server flavor deserialises safely', () {
    final settings = Fragment$WebInterfaceSettingsDto.fromJson({
      '__typename': 'SettingsType',
      'webUIFlavor': 'FUTURE',
      'webUIChannel': 'STABLE',
      'webUIUpdateCheckInterval': 12,
    });
    expect(settings.webUIFlavor, Enum$WebUIFlavor.$unknown);
    expect(settings.webUIChannel, Enum$WebUIChannel.STABLE);
  });

  testWidgets(
    'unsupported servers show an explanation without setting pickers',
    (tester) async {
      final server = await _pump(tester, legacyAccountAccess);
      expect(server.operations, contains('WebInterfaceSettings'));
      expect(find.text('Web interface'), findsOneWidget);
      expect(
        find.text('This server does not support web interface settings.'),
        findsOneWidget,
      );
      expect(find.text('Interface'), findsNothing);
      expect(find.text('Update channel'), findsNothing);
      expect(find.text('Automatic updates'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'without manage settings permission hides pickers and skips settings query',
    (tester) async {
      final server = await _pump(
        tester,
        AccountAccess(capability: AccountCapability.supported),
      );
      expect(server.operations, isNot(contains('WebInterfaceSettings')));
      expect(
        server.operations,
        isNot(contains('SupportedWebInterfaceFlavors')),
      );
      expect(find.text('Interface'), findsNothing);
      expect(find.text('Update channel'), findsNothing);
      expect(find.text('Automatic updates'), findsNothing);
      expect(find.text('Installed version'), findsOneWidget);
      expect(find.text('v1.5.0 · Stable'), findsOneWidget);
      expect(find.text('Check for update'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
