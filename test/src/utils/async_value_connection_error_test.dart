// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
import 'package:tsumiru/src/utils/network/graphql_errors.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';
import 'package:tsumiru/src/widgets/server_unreachable_view.dart';

const _unsupportedMessage =
    "This server uses a sign-in method the browser version can't use. Set the server's authentication mode to UI login, or use the Android, iOS or desktop app.";

Widget _host(AsyncValue<int> async,
        {VoidCallback? refresh,
        bool escapeHatch = false,
        bool catalogAvailable = false,
        List<Override> extraOverrides = const []}) =>
    ProviderScope(
    overrides: [
      offlineCatalogAvailableProvider
          .overrideWith((ref) async => catalogAvailable),
      ...extraOverrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              async.showUiWhenData(context, (d) => Text('data $d'),
                  refresh: refresh, offlineEscapeHatch: escapeHatch),
        ),
      ),
    ));

// Web overrides: the browser flag plus a saved sign-in method, as the
// server-unreachable view reads them.
Future<List<Override>> _webOverrides(
    {required bool isWeb, AuthType? savedAuthType}) async {
  SharedPreferences.setMockInitialValues({
    if (savedAuthType != null) 'authType': savedAuthType.index,
  });
  return [
    isWebProvider.overrideWithValue(isWeb),
    sharedPreferencesProvider.overrideWithValue(
      await SharedPreferences.getInstance(),
    ),
  ];
}

// A non-JSON GraphQL answer in its production wrapping: the repository throws
// the message exception around the operation exception.
OperationMessageException _notJsonError(int status, String snippet) =>
    OperationMessageException(OperationException(
      linkException: HttpLinkParserException(
        originalException: ServerNotJsonException(status, snippet),
        originalStackTrace: StackTrace.empty,
        response: http.Response(snippet, status),
      ),
    ));

// A genuine unreachable-server failure as it arrives in the app: the GraphQL
// wrapper around a ServerException whose cause is a socket error.
OperationMessageException _connectionError() => OperationMessageException(
      OperationException(
        linkException: ServerException(
          parsedResponse: null,
          originalException: const SocketException('unreachable'),
        ),
      ),
    );

void main() {
  testWidgets('a connection failure shows the server-unreachable view',
      (tester) async {
    await tester.pumpWidget(
      _host(AsyncError(_connectionError(), StackTrace.current), refresh: () {}),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ServerUnreachableView), findsOneWidget);
    expect(find.text("Can't reach your server"), findsOneWidget);
  });

  testWidgets('an ordinary error still shows the generic error, not that view',
      (tester) async {
    await tester.pumpWidget(
      _host(AsyncError<int>('boom', StackTrace.current)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ServerUnreachableView), findsNothing);
    expect(find.text('boom'), findsOneWidget);
  });

  // The live 3:03 failure, end to end: proxy answers 502 HTML for a dead
  // upstream -> parser wraps the decoder throw -> the app treats it as
  // unreachable and offers the offline library.
  testWidgets('a proxied 502 lands on the unreachable view with View offline',
      (tester) async {
    final e = OperationMessageException(OperationException(
      linkException: HttpLinkParserException(
        originalException: const ServerNotJsonException(502, '<html>'),
        originalStackTrace: StackTrace.empty,
        response: http.Response('<html>', 502),
      ),
    ));
    await tester.pumpWidget(_host(
      AsyncError<int>(e, StackTrace.current),
      refresh: () {},
      escapeHatch: true,
      catalogAvailable: true,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ServerUnreachableView), findsOneWidget);
    expect(find.text('View offline'), findsOneWidget);
  });

  // The error must stay on screen; the pin is a bypass, never a mask.
  testWidgets(
      'a generic error offers View offline when the screen honors the pin '
      'and a catalog exists', (tester) async {
    await tester.pumpWidget(_host(
      AsyncError<int>('boom', StackTrace.current),
      escapeHatch: true,
      catalogAvailable: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
    expect(find.text('View offline'), findsOneWidget);
  });

  testWidgets('no View offline on a generic error without a catalog',
      (tester) async {
    await tester.pumpWidget(_host(
      AsyncError<int>('boom', StackTrace.current),
      escapeHatch: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('View offline'), findsNothing);
  });

  testWidgets(
      'a web 404 "Not Found" with a saved basic login explains the mode',
      (tester) async {
    await tester.pumpWidget(_host(
      AsyncError<int>(
          _notJsonError(404, 'Not Found'), StackTrace.current),
      extraOverrides: await _webOverrides(
          isWeb: true, savedAuthType: AuthType.basic),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ServerUnreachableView), findsOneWidget);
    expect(find.text(_unsupportedMessage), findsOneWidget);
  });

  testWidgets('a web 404 with another body keeps the generic error',
      (tester) async {
    await tester.pumpWidget(_host(
      AsyncError<int>(
          _notJsonError(404, '<html>proxy 404</html>'),
          StackTrace.current),
      extraOverrides:
          await _webOverrides(isWeb: true, savedAuthType: AuthType.basic),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ServerUnreachableView), findsNothing);
    expect(find.text('Server returned a non-JSON response (HTTP 404)'),
        findsOneWidget);
  });

  testWidgets('a native 404 "Not Found" keeps the generic error',
      (tester) async {
    await tester.pumpWidget(_host(
      AsyncError<int>(
          _notJsonError(404, 'Not Found'), StackTrace.current),
      extraOverrides: await _webOverrides(
          isWeb: false, savedAuthType: AuthType.basic),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ServerUnreachableView), findsNothing);
    expect(find.text('Server returned a non-JSON response (HTTP 404)'),
        findsOneWidget);
  });
}
