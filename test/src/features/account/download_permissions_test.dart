import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/manga_book/data/downloads/downloads_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/downloads_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/widgets/downloads_fab.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/presentation/keep_rule_picker.dart';
import 'package:tsumiru/src/features/offline/presentation/offline_save_button.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'management_permissions_test.dart' show RejectedRequestLink;

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

  for (final capability in AccountCapability.values) {
    test('$capability queue permission admission', () async {
      final link = RejectedRequestLink();
      final client = GraphQLClient(link: link, cache: GraphQLCache());
      final repo = DownloadsRepository(
        client,
        client,
        permissions: AccountPermissionGuard(
          () => AccountAccess(capability: capability),
        ),
      );
      for (final action in <Future<dynamic> Function()>[
        repo.startDownloads,
        repo.stopDownloads,
        repo.clearDownloads,
        () => repo.addChaptersBatchToDownloadQueue([1]),
        () => repo.removeChapterFromDownloadQueue(1),
        () => repo.reorderDownload(1, 0),
      ]) {
        await expectLater(
          action(),
          throwsA(
            capability == AccountCapability.unsupported
                ? isNot(isA<AccountPermissionDenied>())
                : isA<AccountPermissionDenied>(),
          ),
        );
      }
      expect(link.calls, capability == AccountCapability.unsupported ? 6 : 0);
    });
  }

  for (final admin in [false, true]) {
    test(
      '${admin ? 'admin' : 'download grant'} admits queue request',
      () async {
        final link = RejectedRequestLink();
        final client = GraphQLClient(link: link, cache: GraphQLCache());
        final access = AccountAccess(
          capability: AccountCapability.supported,
          user: Fragment$AccountDto(
            id: 2,
            username: 'user',
            roles: [admin ? Enum$UserRole.ADMIN : Enum$UserRole.USER],
            permissions: admin ? [] : [Enum$UserPermission.DOWNLOAD_CHAPTERS],
          ),
        );
        final repo = DownloadsRepository(
          client,
          client,
          permissions: AccountPermissionGuard(() => access),
        );
        await expectLater(
          repo.addChaptersBatchToDownloadQueue([1]),
          throwsA(isNot(isA<AccountPermissionDenied>())),
        );
        expect(link.calls, 1);
      },
    );
  }

  for (final capability in [
    AccountCapability.unknown,
    AccountCapability.supported,
  ]) {
    for (final status in [DownloaderState.STARTED, DownloaderState.STOPPED]) {
      testWidgets('$capability disables server $status control', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settledAccountAccessProvider.overrideWithValue(
                AccountAccess(capability: capability),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                floatingActionButton: DownloadsFab(status: status),
              ),
            ),
          ),
        );
        expect(
          tester
              .widget<FloatingActionButton>(find.byType(FloatingActionButton))
              .onPressed,
          isNull,
        );
      });
    }
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
        .where((tile) => tile.leading is Icon);
    expect(choices, hasLength(5));
    expect(choices.every((tile) => tile.onTap == null), true);
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
