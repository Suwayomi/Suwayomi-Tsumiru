// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/utils/network/graphql_errors.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
import 'package:tsumiru/src/widgets/server_unreachable_view.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';

Widget _host(
  AsyncValue<int> async, {
  VoidCallback? refresh,
  bool escapeHatch = false,
  bool catalogAvailable = false,
}) => ProviderScope(
  overrides: [
    offlineCatalogAvailableProvider.overrideWith(
      (ref) async => catalogAvailable,
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => async.showUiWhenData(
          context,
          (d) => Text('data $d'),
          refresh: refresh,
          offlineEscapeHatch: escapeHatch,
        ),
      ),
    ),
  ),
);

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
  testWidgets('a connection failure shows the server-unreachable view', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(AsyncError(_connectionError(), StackTrace.current), refresh: () {}),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ServerUnreachableView), findsOneWidget);
    expect(find.text("Can't reach your server"), findsOneWidget);
  });

  testWidgets(
    'an ordinary error still shows the generic error, not that view',
    (tester) async {
      await tester.pumpWidget(
        _host(AsyncError<int>('boom', StackTrace.current)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ServerUnreachableView), findsNothing);
      expect(find.text('boom'), findsOneWidget);
    },
  );

  // The live 3:03 failure, end to end: proxy answers 502 HTML for a dead
  // upstream -> parser wraps the decoder throw -> the app treats it as
  // unreachable and offers the offline library.
  testWidgets('a proxied 502 lands on the unreachable view with View offline', (
    tester,
  ) async {
    final e = OperationMessageException(
      OperationException(
        linkException: HttpLinkParserException(
          originalException: const ServerNotJsonException(502, '<html>'),
          originalStackTrace: StackTrace.empty,
          response: http.Response('<html>', 502),
        ),
      ),
    );
    await tester.pumpWidget(
      _host(
        AsyncError<int>(e, StackTrace.current),
        refresh: () {},
        escapeHatch: true,
        catalogAvailable: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ServerUnreachableView), findsOneWidget);
    expect(find.text('View offline'), findsOneWidget);
  });

  // The error must stay on screen; the pin is a bypass, never a mask.
  testWidgets(
    'a generic error offers View offline when the screen honors the pin '
    'and a catalog exists',
    (tester) async {
      await tester.pumpWidget(
        _host(
          AsyncError<int>('boom', StackTrace.current),
          escapeHatch: true,
          catalogAvailable: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('boom'), findsOneWidget);
      expect(find.text('View offline'), findsOneWidget);
    },
  );

  testWidgets('no View offline on a generic error without a catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(AsyncError<int>('boom', StackTrace.current), escapeHatch: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('View offline'), findsNothing);
  });
}
