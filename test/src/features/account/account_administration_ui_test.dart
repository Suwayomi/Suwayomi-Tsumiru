import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/account/presentation/account_admin_dialogs.dart';
import 'package:tsumiru/src/features/account/presentation/account_codes_screen.dart';
import 'package:tsumiru/src/features/account/presentation/manage_users_screen.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'account_administration_test.dart' show AdminLink, adminAccess;

Map<String, dynamic> user(int id, String username) => {
  '__typename': 'UserType',
  'id': id,
  'username': username,
  'roles': ['USER'],
  'permissions': ['DOWNLOAD_CHAPTERS'],
};

void main() {
  late AdminLink link;
  late AccountAccess access;
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool admin = false,
    bool granted = true,
  }) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    access = adminAccess(admin: admin, granted: granted);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settledAccountAccessProvider.overrideWithValue(access),
          accountRepositoryProvider.overrideWithValue(
            AccountRepository(
              GraphQLClient(link: link, cache: GraphQLCache()),
              access: () => access,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => link = AdminLink());

  testWidgets('search resets paging and the list can move forward and back', (
    tester,
  ) async {
    link.respond = (request) => Response(
      response: {},
      data: {
        '__typename': 'Query',
        'users': {
          '__typename': 'UserNodeList',
          'nodes': [
            user(
              request.variables['after'] == null ? 4 : 5,
              request.variables['filter'] != null
                  ? 'search-match'
                  : request.variables['after'] == null
                  ? 'first-reader'
                  : 'second-reader',
            ),
          ],
          'totalCount': 26,
          'pageInfo': {
            '__typename': 'PageInfo',
            'hasNextPage':
                request.variables['after'] == null &&
                request.variables['filter'] == null,
            'hasPreviousPage': request.variables['after'] != null,
            'startCursor': '1',
            'endCursor': '25',
          },
        },
      },
    );
    await pump(tester, const ManageUsersScreen());
    expect(
      find.text('first-reader'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    const unsupported =
        'User deletion is not currently supported on this server.';
    expect(find.text(unsupported), findsNothing);
    final requestsBeforeDelete = link.requests.length;
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text(unsupported), findsOneWidget);
    expect(find.byType(EditAccountDialog), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text(unsupported), findsNothing);
    expect(find.text('first-reader'), findsOneWidget);
    expect(link.requests.length, requestsBeforeDelete);
    expect(find.text('Previous page'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('second-reader'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(link.requests.last.variables['after'], '25');
    await tester.tap(find.text('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('first-reader'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'search');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('search-match'), findsOneWidget);
    expect(find.text('Previous page'), findsNothing);
    expect(find.text('Next'), findsNothing);
    expect(link.requests.last.variables['after'], isNull);
    expect(link.requests.last.variables['filter'], {
      'username': {'includesInsensitive': 'search'},
    });
  });

  testWidgets('denied administration screen sends no requests', (tester) async {
    await pump(tester, const ManageUsersScreen(), granted: false);
    expect(find.text('Create account'), findsNothing);
    expect(link.requests, isEmpty);
  });

  testWidgets('built-in user is immutable even for administrators', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(
        body: EditAccountDialog(
          user: Fragment$AccountDto.fromJson(user(1, 'admin')),
        ),
      ),
      admin: true,
    );
    expect(find.text('Save'), findsNothing);
    expect(find.text('Create recovery code'), findsNothing);
    for (final widget in tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    )) {
      expect(widget.onChanged, isNull);
    }
    expect(link.requests, isEmpty);
  });

  testWidgets(
    'code revoke requires confirmation and cancel sends no mutation',
    (tester) async {
      link.respond = (_) => Response(
        response: {},
        data: {
          '__typename': 'Query',
          'userCodes': [
            {
              '__typename': 'UserCodeType',
              'id': 7,
              'purpose': 'RECOVERY',
              'createdAt': '1800000000',
              'expiresAt': '1900000000',
              'createdBy': {
                '__typename': 'UserType',
                'id': 1,
                'username': 'admin',
              },
              'user': {'__typename': 'UserType', 'id': 5, 'username': 'reader'},
            },
          ],
        },
      );
      await pump(tester, const AccountCodesScreen());
      await tester.tap(find.text('Revoke code'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Revoke this code?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(link.requests, hasLength(1));
    },
  );
}
