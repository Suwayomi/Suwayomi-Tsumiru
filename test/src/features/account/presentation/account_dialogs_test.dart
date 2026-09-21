import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/account_actions.dart';
import 'package:tsumiru/src/features/account/presentation/account_code_dialog.dart';
import 'package:tsumiru/src/features/account/presentation/account_password_dialog.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Future<void> openDialog(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, List<String> values) async {
  for (var i = 0; i < values.length; i++) {
    await tester.enterText(find.byType(TextFormField).at(i), values[i]);
  }
}

void main() {
  testWidgets(
    'registration validates, trims identifiers and preserves password whitespace',
    (tester) async {
      final submissions = <List<String?>>[];
      await openDialog(
        tester,
        AccountCodeDialog(
          mode: AccountCodeMode.registration,
          onSubmit: ({required code, username, required password}) async {
            submissions.add([code, username, password]);
          },
        ),
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(submissions, isEmpty);
      expect(find.text('Enter a code'), findsOneWidget);
      await fill(tester, [' code ', ' alice ', ' secret ', 'different']);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(submissions, isEmpty);
      await tester.enterText(find.byType(TextFormField).last, ' secret ');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(submissions, [
        ['code', 'alice', ' secret '],
      ]);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'recovery blocks duplicate submission and retains server error for retry',
    (tester) async {
      var calls = 0;
      final pending = Completer<void>();
      await openDialog(
        tester,
        AccountCodeDialog(
          mode: AccountCodeMode.recovery,
          onSubmit: ({required code, username, required password}) {
            calls++;
            expect(code, 'recovery');
            expect(username, isNull);
            expect(password, ' new password ');
            return calls == 1 ? pending.future : Future.value();
          },
        ),
      );
      expect(find.byType(TextFormField), findsNWidgets(3));
      await fill(tester, [' recovery ', ' new password ', ' new password ']);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<PopScope>(find.byType(PopScope).last).canPop,
        isFalse,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      )) {
        expect(field.enabled, isFalse);
      }
      pending.completeError(
        OperationException(
          graphqlErrors: [
            const GraphQLError(message: 'Invalid or expired code'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Invalid or expired code'), findsOneWidget);
      expect(calls, 1);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        ' recovery ',
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'password change validates confirmation and preserves both passwords',
    (tester) async {
      List<String>? submitted;
      await openDialog(
        tester,
        AccountPasswordDialog(
          onSubmit: ({required currentPassword, required newPassword}) async {
            submitted = [currentPassword, newPassword];
          },
        ),
      );
      for (final field in tester.widgetList<EditableText>(
        find.byType(EditableText),
      )) {
        expect(field.obscureText, isTrue);
      }
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(submitted, isNull);
      await fill(tester, [' old ', ' new ', 'wrong']);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, ' new ');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(submitted, [' old ', ' new ']);
    },
  );

  testWidgets('password failure restores the form after loading', (
    tester,
  ) async {
    final pending = Completer<void>();
    await openDialog(
      tester,
      AccountPasswordDialog(
        onSubmit: ({required currentPassword, required newPassword}) =>
            pending.future,
      ),
    );
    await fill(tester, ['old', 'new', 'new']);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.completeError(const SocketException('private transport detail'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AccountPasswordDialog));
    expect(
      find.text(AppLocalizations.of(context)!.authTestConnectionFailedNetwork),
      findsOneWidget,
    );
    expect(find.textContaining('private transport detail'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'old',
    );
  });

  for (final confirmed in [false, true]) {
    testWidgets(
      'password outcome explains sign-in requirement: confirmed=$confirmed',
      (tester) async {
        await openDialog(
          tester,
          AccountPasswordDialog(
            onSubmit: ({required currentPassword, required newPassword}) async {
              if (confirmed) throw const AccountPasswordSignInRequired();
              throw const AccountPasswordUnconfirmed();
            },
          ),
        );
        await fill(tester, ['old', 'new', 'new']);
        await tester.tap(find.byType(ElevatedButton));
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AccountPasswordDialog)),
        )!;
        expect(
          find.text(
            confirmed
                ? l10n.accountPasswordSignInRequired
                : l10n.accountPasswordUnconfirmed,
          ),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );
  }

  for (final passwordDialog in [false, true]) {
    testWidgets('completion after unmount is safe: password=$passwordDialog', (
      tester,
    ) async {
      final pending = Completer<void>();
      await openDialog(
        tester,
        passwordDialog
            ? AccountPasswordDialog(
                onSubmit: ({required currentPassword, required newPassword}) =>
                    pending.future,
              )
            : AccountCodeDialog(
                mode: AccountCodeMode.recovery,
                onSubmit: ({required code, username, required password}) =>
                    pending.future,
              ),
      );
      await fill(tester, ['value', 'password', 'password']);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
