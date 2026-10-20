import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/account/presentation/account_code_dialog.dart';
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

}
