import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/settings/data/user_settings.dart';
import 'package:tsumiru/src/features/settings/domain/settings/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/server_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/cloud_flare/cloud_flare_section.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/data/images_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/graphql/__generated__/images.graphql.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/images/images_section.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/opds/data/opds_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/opds/opds_section.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/input_popup/settings_prop_tile.dart';

class _UndefinedFieldLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    yield Response(
      response: {},
      errors: [
        GraphQLError(
          message:
              "Validation error (FieldUndefined@[flareSolverrAsResponseFallback]) : Field 'flareSolverrAsResponseFallback' in type 'SettingsType' is undefined",
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'unsupported response fallback resolves null and hides its switch',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: AccountCapability.unsupported),
          ),
          serverSettingsRepositoryProvider.overrideWith(
            (ref) => ServerSettingsRepository(
              GraphQLClient(link: _UndefinedFieldLink(), cache: GraphQLCache()),
              permissions: ref.watch(accountPermissionGuardProvider),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(flareSolverrFallbackProvider.future), isNull);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CloudFlareSection(
                cloudFlareDto: Fragment$CloudFlareBypassDto(
                  flareSolverrEnabled: true,
                  flareSolverrSessionName: 'default',
                  flareSolverrSessionTtl: 15,
                  flareSolverrTimeout: 60,
                  flareSolverrUrl: 'http://localhost:8191',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Response fallback'), findsNothing);
    },
  );

  group('personal OPDS and image settings', () {
    for (final scenario in [
      (
        name: 'reader ready',
        capability: AccountCapability.supported,
        manage: false,
        state: PersonalSettingsState.ready,
        editable: true,
        adminRows: false,
      ),
      (
        name: 'reader loading',
        capability: AccountCapability.supported,
        manage: false,
        state: PersonalSettingsState.loading,
        editable: false,
        adminRows: false,
      ),
      (
        name: 'reader unavailable',
        capability: AccountCapability.supported,
        manage: false,
        state: PersonalSettingsState.unavailable,
        editable: false,
        adminRows: false,
      ),
      (
        name: 'admin ready',
        capability: AccountCapability.supported,
        manage: true,
        state: PersonalSettingsState.ready,
        editable: true,
        adminRows: true,
      ),
      (
        name: 'admin unavailable',
        capability: AccountCapability.supported,
        manage: true,
        state: PersonalSettingsState.unavailable,
        editable: false,
        adminRows: true,
      ),
      (
        name: 'legacy server',
        capability: AccountCapability.unsupported,
        manage: false,
        state: PersonalSettingsState.unavailable,
        editable: true,
        adminRows: true,
      ),
      (
        name: 'unknown capability',
        capability: AccountCapability.unknown,
        manage: false,
        state: PersonalSettingsState.ready,
        editable: false,
        adminRows: true,
      ),
    ]) {
      testWidgets(scenario.name, (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              graphQlClientProvider.overrideWithValue(
                GraphQLClient(
                  link: _UndefinedFieldLink(),
                  cache: GraphQLCache(),
                ),
              ),
              settledAccountAccessProvider.overrideWithValue(
                AccountAccess(
                  capability: scenario.capability,
                  user: Fragment$AccountDto(
                    id: 2,
                    username: 'reader',
                    roles: const [Enum$UserRole.USER],
                    permissions: scenario.manage
                        ? [Enum$UserPermission.MANAGE_SETTINGS]
                        : [],
                  ),
                ),
              ),
              personalSettingsStateProvider.overrideWithValue(scenario.state),
              opdsSettingsProvider.overrideWith(
                (ref) async => (
                  useBinaryFileSizes: false,
                  itemsPerPage: 100,
                  enablePageReadProgress: true,
                  markAsReadOnDownload: false,
                  showOnlyUnreadChapters: false,
                  showOnlyDownloadedChapters: false,
                  skipChapterMetadataFeed: false,
                  chapterSortOrder: Enum$SortOrder.ASC,
                  cbzMimetype: Enum$CbzMediaType.MODERN,
                ),
              ),
              imagesDownloadSettingsProvider.overrideWith(
                (ref) async =>
                    Fragment$ImagesDownloadSettingsDto(downloadConversions: []),
              ),
              serveConversionsProvider.overrideWith((ref) async => []),
              clearCachedImagesSupportProvider.overrideWith(
                (ref) async => true,
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: Column(children: [OpdsSection(), ImagesSection()]),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final opds = find.byType(OpdsSection);
        final props = tester.widgetList<SettingsPropTile>(
          find.descendant(of: opds, matching: find.byType(SettingsPropTile)),
        );
        expect(props, hasLength(7));
        for (final tile in props) {
          expect(
            tile.type.onChanged != null,
            scenario.editable,
            reason: tile.title,
          );
        }
        final tiles = tester.widgetList<ListTile>(
          find.descendant(of: opds, matching: find.byType(ListTile)),
        );
        expect(tiles, hasLength(9));
        for (final tile in tiles) {
          expect(tile.onTap != null, scenario.editable);
        }

        final context = tester.element(find.byType(ImagesSection));
        final l10n = AppLocalizations.of(context)!;
        expect(
          find.text(l10n.imageProcessingClearCache),
          scenario.adminRows ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(l10n.imageDownloadProcessing),
          scenario.adminRows ? findsOneWidget : findsNothing,
        );
        expect(find.text(l10n.imageServeProcessing), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
