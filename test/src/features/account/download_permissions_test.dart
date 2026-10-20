import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/manga_book/data/downloads/downloads_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/presentation/keep_rule_picker.dart';
import 'package:tsumiru/src/features/offline/presentation/offline_save_button.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

void main() {
  for (final data in <Map<String, dynamic>?>[
    null,
    {'enqueueChapterDownloads': null},
  ]) {
    test('enqueue rejects absent payload $data', () async {
      final client = GraphQLClient(
        link: Link.function(
          (request, [forward]) =>
              Stream.value(Response(data: data, response: const {})),
        ),
        cache: GraphQLCache(),
      );
      final repo = DownloadsRepository(
        client,
        client,
        permissions: AccountPermissionGuard(
          () => AccountAccess(capability: AccountCapability.unsupported),
        ),
      );
      await expectLater(
        repo.addChaptersBatchToDownloadQueue([1]),
        throwsA(isNot(isA<AccountPermissionDenied>())),
      );
    });
  }

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

  for (final state in [
    OfflineDeviceState.none,
    OfflineDeviceState.error,
    OfflineDeviceState.downloaded,
  ]) {
    testWidgets('denied device $state action keeps local removal available', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settledAccountAccessProvider.overrideWithValue(
              AccountAccess(capability: AccountCapability.supported),
            ),
            offlineEnabledProvider.overrideWithValue(true),
            offlineChapterStateProvider(
              1,
            ).overrideWith((ref) => Stream.value(state)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: OfflineSaveButton(chapterId: 1)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        state == OfflineDeviceState.downloaded ? isNotNull : isNull,
      );
    });
  }
}
