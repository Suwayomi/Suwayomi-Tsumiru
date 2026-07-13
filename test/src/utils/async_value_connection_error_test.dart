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
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
import 'package:tsumiru/src/widgets/server_unreachable_view.dart';

Widget _host(AsyncValue<int> async, {VoidCallback? refresh}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              async.showUiWhenData(context, (d) => Text('data $d'),
                  refresh: refresh),
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
}
