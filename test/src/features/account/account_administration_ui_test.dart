import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/account/presentation/manage_users_screen.dart';
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

}
