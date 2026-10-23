import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:gql/language.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/account/presentation/manage_users_screen.dart';
import 'package:tsumiru/src/features/account/presentation/account_admin_dialogs.dart';
import 'package:tsumiru/src/features/account/presentation/account_codes_screen.dart';
import 'package:tsumiru/src/features/account/presentation/account_permission_labels.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'account_administration_test.dart' show AdminLink, adminAccess;

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

  testWidgets('denied administration screen sends no requests', (tester) async {
    await pump(tester, const ManageUsersScreen(), granted: false);
    expect(find.text('Create account'), findsNothing);
    expect(link.requests, isEmpty);
  });

  Widget issueButton() => Consumer(
    builder: (context, ref, _) => Scaffold(
      body: TextButton(
        onPressed: () => issueAccountCode(context, ref),
        child: const Text('Issue'),
      ),
    ),
  );

  Response respond(Request request, {required bool supported}) {
    final query = printNode(request.operation.document);
    if (query.contains('query AccountPermissionCapability')) {
      final input = query.contains('inputFields');
      return Response(
        response: {},
        data: {
          '__type': {
            input ? 'inputFields' : 'fields': [
              if (supported)
                {
                  'name': query.contains('RegisterInput')
                      ? 'userPermissions'
                      : 'permissions',
                },
            ],
          },
        },
      );
    }
    return Response(
      response: {},
      data: {
        '__typename': 'Mutation',
        'createRegistrationCode': {
          '__typename': 'CreateRegistrationCodePayload',
          'code': 'chosen-permissions-code',
          'expiresAt': '1900000000',
        },
      },
    );
  }

  testWidgets('creating an invite sends the chosen permissions', (
    tester,
  ) async {
    link.respond = (request) => respond(request, supported: true);
    await pump(tester, issueButton());
    await tester.tap(find.text('Issue'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountPermissionPicker), findsOneWidget);
    final external = find.widgetWithText(
      SwitchListTile,
      'Install extension files',
    );
    expect(tester.widget<SwitchListTile>(external).value, isTrue);
    await tester.tap(external);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    final mutation = link.requests.singleWhere(
      (request) => printNode(
        request.operation.document,
      ).contains('mutation CreateRegistrationCode'),
    );
    expect(mutation.variables['input'], {
      'permissions': [
        'DOWNLOAD_CHAPTERS',
        'INSTALL_EXTENSIONS',
        'UNINSTALL_EXTENSIONS',
      ],
    });
    expect(find.text('chosen-permissions-code'), findsOneWidget);
  });

  testWidgets(
    'creation pickers stay hidden when permission fields are absent',
    (tester) async {
      link.respond = (request) => respond(request, supported: false);
      await pump(tester, const Scaffold(body: CreateAccountDialog()));
      expect(find.byType(AccountPermissionPicker), findsNothing);
      await pump(tester, issueButton());
      await tester.tap(find.text('Issue'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountPermissionPicker), findsNothing);
      expect(find.byType(RegistrationCodePermissionsDialog), findsNothing);
      expect(find.text('chosen-permissions-code'), findsOneWidget);
      final mutation = link.requests.singleWhere(
        (request) => printNode(
          request.operation.document,
        ).contains('mutation CreateRegistrationCode'),
      );
      expect(mutation.variables['input'], isEmpty);
    },
  );
}
