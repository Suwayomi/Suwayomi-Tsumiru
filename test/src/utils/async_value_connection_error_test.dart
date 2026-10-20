// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';
import 'package:tsumiru/src/utils/network/graphql_errors.dart';
import 'package:tsumiru/src/widgets/server_unreachable_view.dart';

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

void main() {
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
}
