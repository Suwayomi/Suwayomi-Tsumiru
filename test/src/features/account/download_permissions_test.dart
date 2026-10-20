import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/offline/presentation/keep_rule_picker.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('denied account cannot select a download-producing keep rule', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: AccountCapability.unknown),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => pickOfflineKeepRule(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final choices = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((tile) => tile.leading is Icon)
        .toList();
    // Five keep options, then "Stop keeping" and "Remove from device".
    expect(choices, hasLength(7));
    // Keeping chapters needs the download permission; stopping a rule and
    // freeing device space do not, so those two stay tappable.
    expect(choices.take(5).every((tile) => tile.onTap == null), true);
    expect(choices.skip(5).every((tile) => tile.onTap != null), true);
  });

}
