import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/data/sign_in_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/graphql/__generated__/sign_in.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/sign_in/sign_in_section.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/platform/web_auth_mode.dart';
import 'package:tsumiru/src/widgets/input_popup/domain/settings_prop_type.dart';
import 'package:tsumiru/src/widgets/input_popup/settings_prop_tile.dart';

Future<void> pumpSection(
  WidgetTester tester, {
  bool accounts = false,
  int userId = 1,
  Enum$AuthMode mode = Enum$AuthMode.UI_LOGIN,
  bool web = false,
  bool blank = false,
  bool absent = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      signInSettingsProvider.overrideWith(
        (ref) async => absent
            ? null
            : Fragment$SignInSettingsDto(
                authMode: mode,
                authUsername: blank ? '' : 'admin',
                authPassword: blank ? '' : 'secret',
                jwtAudience: 'suwayomi',
                jwtTokenExpiry: 'PT5M',
                jwtRefreshExpiry: 'PT1440H',
              ),
      ),
      signInAccountsCapabilityProvider.overrideWith(
        (ref) async => accounts
            ? AccountCapability.supported
            : AccountCapability.unsupported,
      ),
      currentAccountProvider.overrideWithValue(
        Fragment$AccountDto(
          id: userId,
          username: 'person',
          permissions: const [Enum$UserPermission.MANAGE_SETTINGS],
          roles: const [],
        ),
      ),
      settledAccountAccessProvider.overrideWithValue(
        AccountAccess(capability: AccountCapability.unsupported),
      ),
      isWebProvider.overrideWithValue(web),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: SignInSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final accounts in [false, true]) {
    for (final userId in [1, 2]) {
      for (final mode in [Enum$AuthMode.NONE, Enum$AuthMode.UI_LOGIN]) {
        testWidgets(
          'credential and UI rows: accounts $accounts, user $userId, $mode',
          (tester) async {
            await pumpSection(
              tester,
              accounts: accounts,
              userId: userId,
              mode: mode,
            );
            final admin =
                !accounts || userId == 1 || mode != Enum$AuthMode.UI_LOGIN;
            expect(
              find.text(accounts ? 'Admin username' : 'Username'),
              admin ? findsOneWidget : findsNothing,
            );
            expect(
              find.text(accounts ? 'Admin password' : 'Password'),
              admin ? findsOneWidget : findsNothing,
            );
            expect(
              find.text('JWT audience claim'),
              mode == Enum$AuthMode.UI_LOGIN ? findsOneWidget : findsNothing,
            );
            expect(
              find.text('Access token expiry'),
              mode == Enum$AuthMode.UI_LOGIN ? findsOneWidget : findsNothing,
            );
            expect(
              find.text('Stay signed in for'),
              mode == Enum$AuthMode.UI_LOGIN ? findsOneWidget : findsNothing,
            );
            if (admin) {
              final password = tester
                  .widgetList<SettingsPropTile>(find.byType(SettingsPropTile))
                  .singleWhere(
                    (row) =>
                        row.title == (accounts ? 'Admin password' : 'Password'),
                  );
              expect(password.subtitle, isNull);
              expect((password.type as TextFieldProp).canObscure, isTrue);
              expect(find.text('secret'), findsNothing);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets('missing fields hide the section', (tester) async {
    await pumpSection(tester, absent: true);
    expect(find.text('Authentication mode'), findsNothing);
  });
  testWidgets('None stays selectable with blank credentials', (tester) async {
    await pumpSection(tester, blank: true);
    await tester.tap(find.text('Authentication mode'));
    await tester.pumpAndSettle();
    final radios = tester.widgetList<RadioListTile>(
      find.byWidgetPredicate((widget) => widget is RadioListTile),
    );
    expect(radios.first.enabled, isTrue);
    expect(radios.skip(1).every((row) => row.enabled == false), isTrue);
  });
  for (final mode in [Enum$AuthMode.BASIC_AUTH, Enum$AuthMode.SIMPLE_LOGIN]) {
    testWidgets('web keeps current $mode visible and permits escape', (
      tester,
    ) async {
      await pumpSection(tester, web: true, mode: mode);
      await tester.tap(find.text('Authentication mode'));
      await tester.pumpAndSettle();
      final rows = tester
          .widgetList<RadioListTile>(
            find.byWidgetPredicate((widget) => widget is RadioListTile),
          )
          .toList();
      expect(rows, hasLength(4));
      expect(rows[0].enabled, isTrue);
      expect(rows[1].enabled, isFalse);
      expect(rows[2].enabled, isFalse);
      expect(rows[3].enabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  test('server duration values round trip in minutes and days', () {
    expect(signInDuration('PT5M').inMinutes, 5);
    expect(signInDuration('PT1440H').inDays, 60);
    expect(signInDuration('P60D'), signInDuration('PT1440H'));
    expect(
      signInDuration('PT1H30M0.5S'),
      const Duration(hours: 1, minutes: 30, milliseconds: 500),
    );
    for (final value in [1, 5, 240]) {
      expect(signInDuration('PT${value}M').inMinutes, value);
    }
    for (final value in [1, 60, 365]) {
      expect(signInDuration('PT${value * 24}H').inDays, value);
    }
  });
}
