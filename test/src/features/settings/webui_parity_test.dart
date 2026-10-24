import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' show MultipartFile;
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/data/backup_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/widgets/backup_flags/backup_flags.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/widgets/backup_flags/backup_flags_dialog.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/database/data/database_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/database/database_section.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../helpers/legacy_account_access.dart';

String _name(Request request) => request.operation.document.definitions
    .whereType<OperationDefinitionNode>()
    .single
    .name!
    .value;

class _Link extends Link {
  _Link(this.reply);
  final Response Function(Request) reply;
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    yield reply(request);
  }
}

Response _data(Map<String, dynamic> data) => Response(
  response: {},
  data: {
    '__typename':
        data.keys.any(
          (key) =>
              key.startsWith('set') ||
              key.startsWith('update') ||
              key.startsWith('create') ||
              key.startsWith('restore'),
        )
        ? 'Mutation'
        : 'Query',
    ...data,
  },
);
Response _unknown(String field) => Response(
  response: {},
  errors: [
    GraphQLError(
      message: 'Cannot query field "$field" on type "SettingsType".',
    ),
  ],
);
GraphQLClient _client(_Link link) =>
    GraphQLClient(link: link, cache: GraphQLCache());

const _database = {
  '__typename': 'SettingsType',
  'databaseType': 'POSTGRESQL',
  'databaseUrl': 'postgresql://localhost/suwayomi',
  'databaseUsername': 'suwayomi',
  'databasePassword': 'secret',
  'useHikariConnectionPool': false,
};
const _auto = {
  '__typename': 'SettingsType',
  'autoBackupIncludeManga': true,
  'autoBackupIncludeCategories': false,
  'autoBackupIncludeChapters': true,
  'autoBackupIncludeTracking': true,
  'autoBackupIncludeHistory': true,
  'autoBackupIncludeClientData': true,
  'autoBackupIncludeServerSettings': true,
};

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  testWidgets(
    'stable Database keeps existing fields when preview fields are unknown',
    (tester) async {
      final link = _Link(
        (request) => _name(request) == 'PreviewDatabaseSettings'
            ? _unknown('databaseSchema')
            : _data({'settings': _database}),
      );
      final container = ProviderContainer(
        overrides: [
          graphQlClientProvider.overrideWithValue(_client(link)),
          databaseSettingsRepositoryProvider.overrideWithValue(
            DatabaseSettingsRepository(
              _client(link),
              permissions: legacyAccountPermissions,
            ),
          ),
          settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(container, const DatabaseSection()));
      await tester.pumpAndSettle();
      expect(find.text('postgresql://localhost/suwayomi'), findsOneWidget);
      expect(find.text('Schema'), findsNothing);
      expect(find.text('Maximum connections'), findsNothing);
      expect(
        await container.read(previewDatabaseSettingsProvider.future),
        isNull,
      );
      expect(
        (await container.read(
          databaseSettingsProvider.future,
        ))!.databaseUsername,
        'suwayomi',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stable backup picker and existing flags survive unsupported user settings',
    (tester) async {
      final link = _Link((request) {
        switch (_name(request)) {
          case 'BackupUserSettingsCapability':
            return _unknown('autoBackupIncludeUserSettings');
          case 'AutoBackupFlags':
            return _data({'settings': _auto});
          case 'UpdateAutoBackupFlags':
            expect(
              (request.variables['settings'] as Map).containsKey(
                'autoBackupIncludeUserSettings',
              ),
              isFalse,
            );
            return _data({
              'setSettings': {
                '__typename': 'SetSettingsPayload',
                'settings': _auto,
              },
            });
          case 'CreateBackup':
            expect(
              (request.variables['flags'] as Map).containsKey(
                'includeUserSettings',
              ),
              isFalse,
            );
            return _data({
              'createBackup': {
                '__typename': 'CreateBackupPayload',
                'clientMutationId': null,
                'url': '/backup.gz',
              },
            });
          case 'RestoreBackup':
            expect(
              (request.variables['flags'] as Map).containsKey(
                'includeUserSettings',
              ),
              isFalse,
            );
            return _data({
              'restoreBackup': {
                '__typename': 'RestoreBackupPayload',
                'clientMutationId': null,
                'id': 'restore',
                'status': {
                  '__typename': 'BackupRestoreStatus',
                  'mangaProgress': 0,
                  'totalManga': 0,
                  'state': 'IDLE',
                },
              },
            });
          default:
            throw StateError('Unexpected ${_name(request)}');
        }
      });
      final repo = BackupSettingsRepository(
        _client(link),
        permissions: legacyAccountPermissions,
      );
      final container = ProviderContainer(
        overrides: [backupSettingsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final auto = await repo.autoBackupFlags();
      expect(auto!.autoBackupIncludeCategories, isFalse);
      await tester.pumpWidget(
        _app(
          container,
          BackupFlagsDialog(
            title: 'Backup data',
            initial: BackupFlags.fromAuto(auto),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Server settings'), findsOneWidget);
      expect(find.text('User settings'), findsNothing);
      const flags = BackupFlags(includeUserSettings: false);
      expect(await repo.createBackup(flags), '/backup.gz');
      expect(
        await repo.restoreBackup(MultipartFile.fromString('backup', ''), flags),
        'restore',
      );
      expect(
        (await repo.updateAutoBackupFlags(flags))!.autoBackupIncludeManga,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
