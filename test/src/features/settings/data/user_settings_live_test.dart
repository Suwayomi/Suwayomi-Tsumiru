import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/auth/data/graphql/__generated__/auth.graphql.dart';
import 'package:tsumiru/src/features/settings/data/settings_repository.dart';
import 'package:tsumiru/src/features/settings/data/user_settings.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/downloads_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/library/data/library_settings_repository.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/utils/extensions/custom_extensions.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['TSUMIRU_ACCOUNT_TESTBED'];
  test(
    'reader personal settings round-trip without changing server interval',
    () async {
      final credentials =
          jsonDecode(await File('$root/credentials.json').readAsString())
              as Map<String, dynamic>;
      final reader = credentials['reader'] as Map<String, dynamic>;
      await HttpOverrides.runZoned(() async {
        final raw = GraphQLClient(
          link: HttpLink('http://127.0.0.1:4598/api/graphql'),
          cache: GraphQLCache(),
        );
        final token = await raw
            .mutate$Login(
              Options$Mutation$Login(
                variables: Variables$Mutation$Login(
                  input: Input$LoginInput(
                    username: reader['username'] as String,
                    password: reader['password'] as String,
                  ),
                ),
              ),
            )
            .getData((data) => data.login.accessToken);
        final client = GraphQLClient(
          link: AuthLink(
            getToken: () async => 'Bearer $token',
          ).concat(HttpLink('http://127.0.0.1:4598/api/graphql')),
          cache: GraphQLCache(),
          defaultPolicies: DefaultPolicies(
            query: Policies(fetch: FetchPolicy.noCache),
          ),
        );
        final account = AccountRepository(client);
        final access = AccountAccess(
          capability: await account.capability(),
          user: await account.current(),
        );
        expect(access.allows(Enum$UserPermission.MANAGE_SETTINGS), isFalse);
        final before = (await account.settings())!;
        final server = SettingsRepository(client);
        final interval =
            (await server.getServerSettings())!.globalUpdateInterval;
        final routing = UserSettingsRouting(
          account: account,
          access: () => access,
          settings: server.getServerSettings,
          updated: () {},
        );
        final library = LibrarySettingsRepository(client, routing: routing);
        final downloads = DownloadsSettingsRepository(client, routing: routing);
        try {
          await library.updateMangaMetaData(!before.updateMangas);
          await library.toggleExcludeCompleted(!before.excludeCompleted);
          await library.toggleExcludeNotStarted(!before.excludeNotStarted);
          await library.toggleExcludeUnreadChapters(
            !before.excludeUnreadChapters,
          );
          await downloads.toggleAutoDownloadNewChapters(
            !before.autoDownloadNewChapters,
          );
          await downloads.updateAutoDownloadNewChaptersLimit(
            before.autoDownloadNewChaptersLimit == 7 ? 8 : 7,
          );
          await downloads.toggleExcludeEntryWithUnreadChapters(
            !before.excludeEntryWithUnreadChapters,
          );
          final after = (await account.settings())!;
          expect(after.updateMangas, !before.updateMangas);
          expect(after.excludeCompleted, !before.excludeCompleted);
          expect(after.excludeNotStarted, !before.excludeNotStarted);
          expect(after.excludeUnreadChapters, !before.excludeUnreadChapters);
          expect(
            after.autoDownloadNewChapters,
            !before.autoDownloadNewChapters,
          );
          expect(
            after.autoDownloadNewChaptersLimit,
            before.autoDownloadNewChaptersLimit == 7 ? 8 : 7,
          );
          expect(
            after.excludeEntryWithUnreadChapters,
            !before.excludeEntryWithUnreadChapters,
          );
          expect(
            (await server.getServerSettings())!.globalUpdateInterval,
            interval,
          );
        } finally {
          await account.setSettings(
            Input$SetUserSettingsInput(
              userSettings: Input$PartialUserSettingsTypeInput(
                updateMangas: before.updateMangas,
                excludeCompleted: before.excludeCompleted,
                excludeNotStarted: before.excludeNotStarted,
                excludeUnreadChapters: before.excludeUnreadChapters,
                autoDownloadNewChapters: before.autoDownloadNewChapters,
                autoDownloadNewChaptersLimit:
                    before.autoDownloadNewChaptersLimit,
                excludeEntryWithUnreadChapters:
                    before.excludeEntryWithUnreadChapters,
              ),
            ),
          );
        }
      }, createHttpClient: _RealHttp().createHttpClient);
    },
    skip: root == null ? 'Requires the isolated account test server' : false,
  );
}
