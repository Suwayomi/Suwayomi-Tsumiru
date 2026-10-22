import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:tsumiru/src/features/library/presentation/category/controller/edit_category_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/settings/presentation/more/more_screen.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/widgets/desktop/desktop_top_bar.dart';

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
  // The previous pump's container/tree, retired at the next pump while still
  // in the test zone: unmounting schedules Riverpod auto-dispose tasks that
  // only drain while the fake clock can elapse, which teardown cannot do.
  ProviderContainer? liveContainer;
  Future<void> pump(
    WidgetTester tester, {
    AccountCapability capability = AccountCapability.supported,
    Fragment$AccountDto? account,
    bool more = false,
    AuthType mode = AuthType.uiLogin,
    bool credentials = true,
  }) async {
    final retired = liveContainer;
    liveContainer = null;
    if (retired != null) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      retired.dispose();
    }
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tester.view.reset();
    tester.view.physicalSize = const Size(600, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The container is owned here, not by the widget tree: the next pump (or
    // the dispose teardown for the last one) retires it while still in the
    // test zone. A cross-test unmount fires on an already-disposed
    // container; the slot registry and search-box cleanup tolerate that via
    // alive/identity guards instead of touching a dead container.
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        // At 600x1500 More mounts the desktop search box, whose results
        // overlay reads these: never hit the network in widget tests.
        loggedInTrackersProvider.overrideWithValue(
          const AsyncData(<Fragment$TrackerDto>[]),
        ),
        libraryTagListProvider.overrideWithValue(const AsyncData(<String>[])),
        libraryMangaListProvider.overrideWith((ref) async => []),
        visibleCategoryListProvider.overrideWithValue(const AsyncData([])),
        failedUpdateCountProvider.overrideWithValue(const AsyncData(0)),
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
    );
    liveContainer = container;
    addTearDown(() {
      // dispose() is idempotent: a retired container is already gone.
      container.dispose();
      if (identical(liveContainer, container)) liveContainer = null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          if (call.method == 'isMaximized') return false;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            null,
          ),
    );
    Widget page() => more ? const MoreScreen() : const AccountScreen();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Native desktop draws the toolbar in the shell bar above the
          // page; narrower surfaces keep the page on its own.
          home: Builder(
            builder: (context) => showsMergedTopBar(context)
                ? Scaffold(
                    body: Column(
                      children: [
                        const DesktopTopBar(),
                        Expanded(child: page()),
                      ],
                    ),
                  )
                : page(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permissions display and sign-out confirmation',
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

    // Sign-out requires confirmation.
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

  testWidgets('More hides the Account entry without account support',
      (tester) async {
    await pump(tester, more: true, capability: AccountCapability.unsupported);
    expect(find.widgetWithIcon(ListTile, Icons.person_rounded), findsNothing);
    await pump(tester, more: true, capability: AccountCapability.unknown);
    expect(
        find.widgetWithIcon(ListTile, Icons.person_rounded), findsOneWidget);
  });
}
