import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
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
            'hasNextPage': request.variables['after'] == null,
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
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('second-reader'), findsOneWidget);
    expect(link.requests.last.variables['after'], 25);
    await tester.tap(find.text('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('first-reader'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'search');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('search-match'), findsOneWidget);
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

  testWidgets(
    'nonadmin permission editor omits role and sends replacement grants',
    (tester) async {
      link.respond = (request) => Response(
        response: {},
        data: {
          '__typename': 'Mutation',
          'updateUser': {
            '__typename': 'UpdateUserPayload',
            'user': user(5, 'reader'),
          },
        },
      );
      await pump(
        tester,
        Scaffold(
          body: EditAccountDialog(
            user: Fragment$AccountDto.fromJson(user(5, 'reader')),
          ),
        ),
      );
      expect(find.byType(DropdownButtonFormField<Enum$UserRole>), findsNothing);
      expect(find.text('ACCESS_NSFW'), findsNothing);
      await tester.tap(find.text('Download chapters'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(link.requests.single.variables['input'], {
        'userId': 5,
        'permissions': [],
      });
    },
  );

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
    'creation errors retain credentials and show the server message',
    (tester) async {
      link.respond = (_) => Response(
        response: {},
        errors: [const GraphQLError(message: 'Username already exists')],
      );
      await pump(tester, const Scaffold(body: CreateAccountDialog()));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'taken');
      await tester.enterText(fields.at(1), 'password');
      await tester.enterText(fields.at(2), 'password');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Username already exists'), findsOneWidget);
      expect(find.text('taken'), findsOneWidget);
      expect(link.requests.single.variables, {
        'input': {'username': 'taken', 'password': 'password'},
      });
    },
  );

  testWidgets(
    'registration code is issued once and can be copied with expiry visible',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      link.respond = (_) => Response(
        response: {},
        data: {
          '__typename': 'Mutation',
          'createRegistrationCode': {
            '__typename': 'CreateRegistrationCodePayload',
            'code': 'invite-once',
            'expiresAt': '1900000000',
          },
        },
      );
      await pump(tester, const Scaffold(body: IssuedAccountCodeDialog()));
      expect(find.text('invite-once'), findsOneWidget);
      expect(find.textContaining('Expires '), findsOneWidget);
      await tester.tap(find.text('Copy to clipboard'));
      await tester.pumpAndSettle();
      expect(copied, 'invite-once');
      expect(link.requests, hasLength(1));
    },
  );

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
  testWidgets('confirmed revocation refreshes outstanding codes', (
    tester,
  ) async {
    var revoked = false;
    link.respond = (request) {
      if (request.variables.containsKey('input')) {
        revoked = true;
        return Response(
          response: {},
          data: {
            '__typename': 'Mutation',
            'revokeUserCode': {
              '__typename': 'RevokeUserCodePayload',
              'clientMutationId': null,
            },
          },
        );
      }
      return Response(
        response: {},
        data: {
          '__typename': 'Query',
          'userCodes': [
            if (!revoked)
              {
                '__typename': 'UserCodeType',
                'id': 7,
                'purpose': 'REGISTRATION',
                'createdAt': '1800000000',
                'expiresAt': '1900000000',
                'createdBy': {
                  '__typename': 'UserType',
                  'id': 1,
                  'username': 'admin',
                },
                'user': null,
              },
          ],
        },
      );
    };
    await pump(tester, const AccountCodesScreen());
    await tester.tap(find.text('Revoke code'));
    await tester.pumpAndSettle();
    expect(revoked, isFalse);
    await tester.tap(find.widgetWithText(TextButton, 'Revoke code').last);
    await tester.pumpAndSettle();
    expect(revoked, isTrue);
    expect(find.text('No outstanding codes'), findsOneWidget);
    expect(
      link.requests
          .where((request) => request.variables.containsKey('input'))
          .single
          .variables,
      {
        'input': {'id': 7},
      },
    );
  });

  testWidgets('administrators can choose a replacement role', (tester) async {
    link.respond = (request) => Response(
      response: {},
      data: {
        '__typename': 'Mutation',
        'updateUser': {
          '__typename': 'UpdateUserPayload',
          'user': user(5, 'reader'),
        },
      },
    );
    await pump(
      tester,
      Scaffold(
        body: EditAccountDialog(
          user: Fragment$AccountDto.fromJson(user(5, 'reader')),
        ),
      ),
      admin: true,
    );
    await tester.tap(find.byType(DropdownButtonFormField<Enum$UserRole>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Administrator').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((link.requests.single.variables['input'] as Map)['role'], 'ADMIN');
  });
}
