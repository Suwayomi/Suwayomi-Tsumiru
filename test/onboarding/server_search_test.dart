// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Widget tests for "Search my network" on the onboarding server step: the
// discovered servers fill the address field, or open a picker when several
// answered. Discovery itself is stubbed through [lanServerScanProvider].

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/onboarding/data/server_discovery.dart';
import 'package:tsumiru/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

const _aboutOk =
    '{"data":{"aboutServer":{"name":"Suwayomi-Server","version":"2.3.2162"}}}';
const _downloadOk = '{"data":{"downloadStatus":{"state":"STOPPED"}}}';

/// A server that confirms via aboutServer and needs no login.
http.Client _openServerClient() => MockClient.streaming((request, body) async {
  final q =
      ((jsonDecode(await body.bytesToString()) as Map)['query'] as String);
  return http.StreamedResponse(
    Stream.value(
      utf8.encode(q.contains('aboutServer') ? _aboutOk : _downloadOk),
    ),
    200,
  );
});

/// Pumps the onboarding wizard on the server step with discovery stubbed to
/// return [results].
Future<void> _pumpServerStep(
  WidgetTester tester,
  List<DiscoveredServer> results,
) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({'onboarding.step': 1});
  final preferences = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(1080, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        onboardingHttpClientProvider.overrideWithValue(_openServerClient),
        lanServerScanProvider.overrideWithValue(() async => results),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OnboardingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _urlFieldText(WidgetTester tester) => tester
    .widget<TextField>(find.widgetWithText(TextField, 'Server URL'))
    .controller!
    .text;

void main() {
  testWidgets('one discovered server fills the URL field and is tested', (
    tester,
  ) async {
    await _pumpServerStep(tester, const [
      DiscoveredServer(
        url: 'http://192.168.2.4:4568',
        name: 'Suwayomi-Server',
        version: '2.3.2162',
      ),
    ]);

    await tester.tap(find.text('Search my network'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a server'), findsNothing);
    expect(_urlFieldText(tester), 'http://192.168.2.4:4568');
    expect(find.textContaining('Connected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('several discovered servers open a picker; a tap fills the URL', (
    tester,
  ) async {
    await _pumpServerStep(tester, const [
      DiscoveredServer(
        url: 'http://192.168.2.4:4567',
        name: 'Suwayomi-Server',
        version: '2.3.2162',
      ),
      DiscoveredServer(url: 'http://192.168.2.9:4568'),
    ]);

    await tester.tap(find.text('Search my network'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a server'), findsOneWidget);
    expect(
      find.text('Suwayomi-Server v2.3.2162 · 192.168.2.4:4567'),
      findsOneWidget,
    );
    expect(find.text('192.168.2.9:4568'), findsOneWidget);

    await tester.tap(find.text('192.168.2.9:4568'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a server'), findsNothing);
    expect(_urlFieldText(tester), 'http://192.168.2.9:4568');
    expect(find.textContaining('Connected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('confirmLanServer', () {
    http.Client respond(int status, String body, [Map<String, String>? h]) =>
        MockClient((_) async => http.Response(body, status, headers: h ?? {}));

    test('keeps a server that answers as Suwayomi, with its name', () async {
      final s = await confirmLanServer(
        'http://h:4568',
        client: respond(
          200,
          '{"data":{"aboutServer":{"name":"Suwayomi-Server","version":"1.0.0"},'
          '"downloadStatus":{"__typename":"DownloadStatus"}}}',
        ),
      );
      expect(s?.url, 'http://h:4568');
      expect(s?.name, 'Suwayomi-Server');
    });

    test('keeps a server that challenges for Basic auth', () async {
      final s = await confirmLanServer(
        'http://h:4567',
        client: respond(401, '', {'www-authenticate': 'Basic realm="x"'}),
      );
      expect(s?.url, 'http://h:4567');
    });

    test('drops something that is not Suwayomi', () async {
      expect(
        await confirmLanServer(
          'http://h:4569',
          client: respond(404, '<html>printer</html>'),
        ),
        isNull,
      );
    });
  });
}
