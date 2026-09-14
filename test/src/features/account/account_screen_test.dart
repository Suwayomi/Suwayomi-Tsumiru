import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/account/data/account_actions.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/account/presentation/account_screen.dart';
import 'package:tsumiru/src/features/auth/data/auth_session_status.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/settings/presentation/more/more_screen.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';

import '../../../helpers/fake_extension_repository.dart';

class ScreenUpdatesRepository extends UpdatesRepository {
  ScreenUpdatesRepository() : super(dummyGraphQLClient(), dummyGraphQLClient());

  @override
  Future<List<MangaDto>> failedUpdates() async => [];
}

class ScreenAccountActions extends AccountActions {
  ScreenAccountActions(super.ref);
  int refreshes = 0;
  int signOuts = 0;
  ({String current, String replacement})? password;
  @override
  Future<void> refreshAccount() async => refreshes++;
  @override
  Future<void> signOut() async => signOuts++;
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    password = (current: currentPassword, replacement: newPassword);
  }
}

class ScreenAuthType extends AuthTypeKey {
  ScreenAuthType(this.mode);
  final AuthType mode;
  @override
  AuthType build() => mode;
}

Fragment$AccountDto user({int id = 2, bool admin = false}) =>
    Fragment$AccountDto(
      id: id,
      username: 'reader',
      roles: [admin ? Enum$UserRole.ADMIN : Enum$UserRole.USER],
      permissions: [
        Enum$UserPermission.DOWNLOAD_CHAPTERS,
        Enum$UserPermission.ACCESS_NSFW,
      ],
    );

void main() {
  late ScreenAccountActions actions;
  Future<void> pump(
    WidgetTester tester, {
    AccountCapability capability = AccountCapability.supported,
    Fragment$AccountDto? account,
    bool more = false,
    AuthType mode = AuthType.uiLogin,
    bool credentials = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tester.view.reset();
    tester.view.physicalSize = const Size(600, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          updatesRepositoryProvider.overrideWithValue(ScreenUpdatesRepository()),
          currentAccountProvider.overrideWithValue(account),
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(
              capability: capability,
              user: capability == AccountCapability.supported ? account : null,
            ),
          ),
          authTypeKeyProvider.overrideWith(() => ScreenAuthType(mode)),
          hasStoredCredentialsProvider.overrideWithValue(credentials),
          accountActionsProvider.overrideWith(
            (ref) => actions = ScreenAccountActions(ref),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: more ? const MoreScreen() : const AccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permissions start collapsed and expand to one allowed grant without NSFW',
    (tester) async {
      await pump(tester, account: user());
      expect(find.text('reader'), findsOneWidget);
      expect(find.text('User'), findsOneWidget);
      expect(find.text('Permissions'), findsOneWidget);
      expect(find.text('1 of 9 allowed'), findsOneWidget);
      expect(find.text('Download chapters'), findsNothing);
      await tester.tap(find.text('Permissions'));
      await tester.pumpAndSettle();
      expect(find.text('Download chapters'), findsOneWidget);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('Restricted'), findsNWidgets(8));
      expect(find.textContaining('NSFW'), findsNothing);
      expect(const AccountRoute().location, '/more/account');
    },
  );

  testWidgets(
    'cached administrator cannot grant permissions or change password',
    (tester) async {
      await pump(
        tester,
        capability: AccountCapability.unknown,
        account: user(admin: true),
      );
      expect(find.text('Administrator'), findsOneWidget);
      expect(find.text('Full access'), findsNothing);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Download chapters'), findsNothing);
      await tester.tap(find.text('Permissions'));
      await tester.pumpAndSettle();
      expect(find.text('Allowed'), findsNothing);
      expect(find.text('Restricted'), findsNothing);
      expect(find.text('Unavailable'), findsNWidgets(10));
      expect(find.textContaining('NSFW'), findsNothing);
      final change = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Change password'),
      );
      expect(change.onTap, isNull);
      expect(find.text('Server'), findsNothing);
    },
  );

  testWidgets('administrator permissions expand to nine allowed grants', (
    tester,
  ) async {
    await pump(tester, account: user(admin: true));
    expect(find.text('Full access'), findsOneWidget);
    expect(find.text('Download chapters'), findsNothing);
    await tester.tap(find.text('Permissions'));
    await tester.pumpAndSettle();
    expect(find.text('Allowed'), findsNWidgets(9));
    expect(find.text('Restricted'), findsNothing);
    expect(find.textContaining('NSFW'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('built-in administrator can open the password dialog', (
    tester,
  ) async {
    await pump(tester, account: user(id: 1, admin: true));
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('Server'), findsNothing);
  });

  testWidgets('built-in password requires verified settings permission', (
    tester,
  ) async {
    await pump(tester, account: user(id: 1));
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Change password'))
          .onTap,
      isNull,
    );
    await pump(
      tester,
      account: user(id: 1, admin: true),
      capability: AccountCapability.unknown,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Change password'))
          .onTap,
      isNull,
    );
  });

  testWidgets('Manage users entry requires a verified grant', (tester) async {
    await pump(tester, account: user());
    expect(find.text('Manage users'), findsNothing);
    await pump(tester, account: user(admin: true));
    expect(find.text('Manage users'), findsOneWidget);
    await pump(
      tester,
      account: user(admin: true),
      capability: AccountCapability.unknown,
    );
    expect(find.text('Manage users'), findsNothing);
  });

  testWidgets('refresh and password dialog invoke account actions', (
    tester,
  ) async {
    await pump(tester, account: user());
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(actions.refreshes, 1);
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'old-password');
    await tester.enterText(fields.at(1), 'new-password');
    await tester.enterText(fields.at(2), 'new-password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Change password'));
    await tester.pumpAndSettle();
    expect(actions.password, (
      current: 'old-password',
      replacement: 'new-password',
    ));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('sign out requires confirmation', (tester) async {
    await pump(tester, account: user());
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(actions.signOuts, 0);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(actions.signOuts, 1);
  });

  testWidgets('More exposes supported account above categories', (
    tester,
  ) async {
    await pump(tester, account: user(), more: true);
    expect(find.text('Account'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Account')).dy,
      lessThan(tester.getTopLeft(find.text('Categories')).dy),
    );
  });

  testWidgets(
    'More keeps bound cached account visible offline and reports missing sign-in',
    (tester) async {
      await pump(
        tester,
        account: user(),
        more: true,
        capability: AccountCapability.unknown,
        credentials: false,
      );
      expect(find.text('Account'), findsOneWidget);
      expect(find.textContaining('Sign-in needed'), findsOneWidget);
    },
  );

  for (final capability in [
    AccountCapability.unknown,
    AccountCapability.unsupported,
  ]) {
    testWidgets(
      'More retains signed-out UI Login entry with $capability capability',
      (tester) async {
        await pump(
          tester,
          more: true,
          credentials: false,
          capability: capability,
        );
        expect(find.text('Account'), findsOneWidget);
        expect(find.textContaining('Sign-in needed'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'signed-out Account disables refresh and opens real sign-in popup with account codes',
    (tester) async {
      await pump(
        tester,
        credentials: false,
        capability: AccountCapability.unknown,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.refresh_rounded),
            )
            .onPressed,
        isNull,
      );
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(actions.refreshes, 0);
      expect(find.text('Sign out'), findsNothing);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginCredentialsPopup), findsOneWidget);
      expect(
        tester
            .widget<LoginCredentialsPopup>(find.byType(LoginCredentialsPopup))
            .authType,
        AuthType.uiLogin,
      );
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Reset password'), findsOneWidget);
    },
  );

  testWidgets(
    'signed-in legacy Account retains sign-out without an account DTO',
    (tester) async {
      await pump(tester, capability: AccountCapability.unsupported);
      expect(find.text('Sign in'), findsNothing);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(actions.signOuts, 1);
    },
  );

  for (final mode in [AuthType.none, AuthType.basic]) {
    testWidgets('More hides unsupported account surface for $mode', (
      tester,
    ) async {
      await pump(
        tester,
        more: true,
        mode: mode,
        capability: AccountCapability.unsupported,
      );
      expect(find.text('Account'), findsNothing);
    });
  }
}
