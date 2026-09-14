import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/account/data/account_permission.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_repository/extension_repository.dart';
import 'package:tsumiru/src/features/browse_center/data/extension_store_repository/extension_store_repository.dart';
import 'package:tsumiru/src/features/browse_center/data/source_repository/source_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/backup/data/backup_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/browse/data/browse_settings_repository.dart';
import 'package:tsumiru/src/features/settings/presentation/server/data/server_settings_repository.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

class RejectedRequestLink extends Link {
  int calls = 0;
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    calls++;
    yield Response(
      response: {},
      errors: [const GraphQLError(message: 'test response')],
    );
  }
}

void main() {
  late RejectedRequestLink link;
  late AccountAccess access;
  late ExtensionRepository extensions;
  late ExtensionStoreRepository stores;
  late SourceRepository sources;
  late ServerSettingsRepository server;
  late BrowseSettingsRepository browse;
  late BackupSettingsRepository backup;
  setUp(() {
    link = RejectedRequestLink();
    final client = GraphQLClient(link: link, cache: GraphQLCache());
    access = AccountAccess(capability: AccountCapability.unknown);
    final guard = AccountPermissionGuard(() => access);
    extensions = ExtensionRepository(client, permissions: guard);
    stores = ExtensionStoreRepository(client, permissions: guard);
    sources = SourceRepository(client, permissions: guard);
    server = ServerSettingsRepository(client, permissions: guard);
    browse = BrowseSettingsRepository(client, permissions: guard);
    backup = BackupSettingsRepository(client, permissions: guard);
  });

  Map<String, Future<dynamic> Function()> actions() => {
    'install': () => extensions.installExtension('pkg'),
    'uninstall': () => extensions.uninstallExtension('pkg'),
    'add store': () => stores.addStore('https://store'),
    'remove store': () => stores.removeStore('https://store'),
    'source preference': () => sources.updateSourcePreferenceById(
      '1',
      Input$SourcePreferenceChangeInput(position: 0, checkBoxState: true),
    ),
    'binding address': () => server.updateIpAddress('0.0.0.0'),
    'binding port': () => server.updatePort(4567),
    'proxy enabled': () => server.toggleSocksProxy(true),
    'proxy version': () => server.updateSocksVersion(5),
    'proxy host': () => server.updateSocksHost('host'),
    'proxy username': () => server.updateSocksUserName('user'),
    'proxy password': () => server.updateSocksPassword('password'),
    'proxy port': () => server.updateSocksPort('1080'),
    'solver enabled': () => server.toggleFlareSolverr(true),
    'solver session': () => server.updateFlareSolverrSessionName('session'),
    'solver ttl': () => server.updateFlareSolverrSessionTtl(10),
    'solver timeout': () => server.updateFlareSolverrTimeout(30),
    'solver url': () => server.updateFlareSolverrUrl('http://solver'),
    'debug logs': () => server.toggleDebugLogs(true),
    'system tray': () => server.toggleSystemTrayEnabled(true),
    'parallel sources': () => browse.updateSourceInParallel(5),
    'local source path': () => browse.updateLocalSourcePath('/manga'),
    'backup path': () => backup.updateBackupLocation('/backup'),
    'backup time': () =>
        backup.updateBackupTime(const TimeOfDay(hour: 1, minute: 0)),
    'backup interval': () => backup.updateBackupInterval(7),
    'backup ttl': () => backup.updateBackupTTL(14),
  };

  for (final capability in [
    AccountCapability.unknown,
    AccountCapability.supported,
  ]) {
    test(
      '$capability management mutations send no requests without grants',
      () async {
        access = AccountAccess(capability: capability);
        for (final entry in actions().entries) {
          await expectLater(
            entry.value(),
            throwsA(isA<AccountPermissionDenied>()),
            reason: entry.key,
          );
        }
        expect(link.calls, 0);
      },
    );
  }

  for (final admin in [false, true]) {
    test(
      '${admin ? 'admin' : 'legacy'} dispatches management mutations',
      () async {
        access = AccountAccess(
          capability: admin
              ? AccountCapability.supported
              : AccountCapability.unsupported,
          user: admin
              ? Fragment$AccountDto(
                  id: 1,
                  username: 'admin',
                  permissions: [],
                  roles: [Enum$UserRole.ADMIN],
                )
              : null,
        );
        for (final entry in actions().entries) {
          await expectLater(
            entry.value(),
            throwsA(isNot(isA<AccountPermissionDenied>())),
            reason: entry.key,
          );
        }
        expect(link.calls, actions().length);
      },
    );
  }

  test(
    'source pin, visibility, extension update and personal backup remain available',
    () async {
      for (final action in <Future<dynamic> Function()>[
        () => sources.setSourcePinned('1', true),
        () => sources.setSourceHidden('1', true),
        () => extensions.updateExtension('pkg'),
        () => backup.createBackup(
          includeCategories: true,
          includeChapters: true,
          includeHistory: true,
          includeTracking: true,
          includeClientData: true,
        ),
      ]) {
        await expectLater(
          action(),
          throwsA(isNot(isA<AccountPermissionDenied>())),
        );
      }
      expect(link.calls, 4);
    },
  );

  testWidgets('external install is rejected before reading a file', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    await expectLater(
      extensions.installExtensionFile(context),
      throwsA(isA<AccountPermissionDenied>()),
    );
    expect(link.calls, 0);
  });
}
