// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/settings/presentation/syncyomi/syncyomi_sync.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

/// A server mid-sync whose socket is unavailable: status queries answer a
/// running sync, the subscription errors immediately.
class _StatusServer extends Link {
  int statusQueries = 0;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    switch (name) {
      case 'LastSyncStatus':
        statusQueries++;
        yield Response(
          response: {},
          data: {
            '__typename': 'Query',
            'lastSyncStatus': {
              '__typename': 'SyncStatus',
              'state': 'STARTED',
              'errorMessage': null,
              'startDate': '1',
              'endDate': null,
            },
          },
        );
      case 'SyncStatusChanged':
        yield const Response(
          response: {},
          errors: [GraphQLError(message: 'socket unavailable')],
        );
      default:
        yield Response(
          response: {},
          errors: [GraphQLError(message: 'unexpected $name')],
        );
    }
  }
}

class _SyncProbe extends HookConsumerWidget {
  const _SyncProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = useSyncYomi(ref);
    return Text(sync.running ? 'running' : 'idle');
  }
}

/// Same running-sync answers, but the subscription delivers once and then
/// goes quiet: the live socket owns the status, so the query poll parks.
class _LiveSocketServer extends _StatusServer {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.document.definitions
        .whereType<OperationDefinitionNode>()
        .single
        .name!
        .value;
    if (name == 'SyncStatusChanged') {
      yield Response(
        response: {},
        data: {
          '__typename': 'Subscription',
          'syncStatusChanged': {
            '__typename': 'SyncStatus',
            'state': 'STARTED',
            'errorMessage': null,
            'startDate': '1',
            'endDate': null,
          },
        },
      );
      return;
    }
    yield* super.request(request, forward);
  }
}

void main() {
  testWidgets('live subscription parks the query poll', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final server = _LiveSocketServer();
    GraphQLClient client() => GraphQLClient(
      link: server,
      cache: GraphQLCache(),
      defaultPolicies: DefaultPolicies(
        query: Policies(fetch: FetchPolicy.noCache),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          graphQlClientProvider.overrideWithValue(client()),
          graphQlSubscriptionClientProvider.overrideWithValue(client()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: _SyncProbe()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('running'), findsOneWidget);
    // Initial read plus the one refresh the socket push triggered.
    final settled = server.statusQueries;
    expect(settled, greaterThanOrEqualTo(1));

    // Parked: no further query polls while the socket owns the status.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump();
    expect(server.statusQueries, settled);
  });

  testWidgets('sync falls back to polling when the socket errors', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final server = _StatusServer();
    GraphQLClient client() => GraphQLClient(
      link: server,
      cache: GraphQLCache(),
      defaultPolicies: DefaultPolicies(
        query: Policies(fetch: FetchPolicy.noCache),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          graphQlClientProvider.overrideWithValue(client()),
          graphQlSubscriptionClientProvider.overrideWithValue(client()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: _SyncProbe()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The query is the initial value and reports a running sync.
    expect(find.text('running'), findsOneWidget);
    final first = server.statusQueries;
    expect(first, greaterThanOrEqualTo(1));

    // The dead socket must not park the 2s query poll.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump();
    expect(server.statusQueries, greaterThan(first));
  });
}
