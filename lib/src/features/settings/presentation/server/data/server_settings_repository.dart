import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../account/data/account_permission.dart';
import '../../../domain/settings/settings.dart';
import 'graphql/__generated__/query.graphql.dart';

part 'server_settings_repository.g.dart';

class ServerSettingsRepository {
  const ServerSettingsRepository(this.ferryClient, {required this.permissions});

  final AccountPermissionGuard permissions;

  final GraphQLClient ferryClient;

  Future<SettingsDto?> updateIpAddress(String ipAddress) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateServerIp(
          Options$Mutation$UpdateServerIp(
            variables: Variables$Mutation$UpdateServerIp(ip: ipAddress),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> updatePort(int port) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdatePort(
          Options$Mutation$UpdatePort(
            variables: Variables$Mutation$UpdatePort(port: port),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> toggleSocksProxy(bool isEnabled) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$ToggleSocksProxy(
          Options$Mutation$ToggleSocksProxy(
            variables: Variables$Mutation$ToggleSocksProxy(
              socksProxyEnabled: isEnabled,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> updateSocksVersion(int newVersion) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateSocksVersion(
          Options$Mutation$UpdateSocksVersion(
            variables: Variables$Mutation$UpdateSocksVersion(
              socksProxyVersion: newVersion,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> updateSocksHost(String value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateSocksHost(
          Options$Mutation$UpdateSocksHost(
            variables: Variables$Mutation$UpdateSocksHost(
              socksProxyHost: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> updateSocksUserName(String value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateSocksUserName(
          Options$Mutation$UpdateSocksUserName(
            variables: Variables$Mutation$UpdateSocksUserName(
              socksProxyUsername: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> updateSocksPassword(String value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateSocksPassword(
          Options$Mutation$UpdateSocksPassword(
            variables: Variables$Mutation$UpdateSocksPassword(
              socksProxyPassword: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> updateSocksPort(String value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateSocksPort(
          Options$Mutation$UpdateSocksPort(
            variables: Variables$Mutation$UpdateSocksPort(
              socksProxyPort: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> toggleFlareSolverr(bool value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$ToggleFlareSolverr(
          Options$Mutation$ToggleFlareSolverr(
            variables: Variables$Mutation$ToggleFlareSolverr(
              flareSolverrEnabled: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> updateFlareSolverrSessionName(String value) =>
      permissions.run(
        Enum$UserPermission.MANAGE_SETTINGS,
        () => ferryClient
            .mutate$UpdateFlareSolverrSessionName(
              Options$Mutation$UpdateFlareSolverrSessionName(
                variables: Variables$Mutation$UpdateFlareSolverrSessionName(
                  flareSolverrSessionName: value,
                ),
              ),
            )
            .getData((data) => data.setSettings.settings),
      );

  Future<SettingsDto?> updateFlareSolverrSessionTtl(int value) =>
      permissions.run(
        Enum$UserPermission.MANAGE_SETTINGS,
        () => ferryClient
            .mutate$UpdateFlareSolverrSessionTtl(
              Options$Mutation$UpdateFlareSolverrSessionTtl(
                variables: Variables$Mutation$UpdateFlareSolverrSessionTtl(
                  flareSolverrSessionTtl: value,
                ),
              ),
            )
            .getData((data) => data.setSettings.settings),
      );

  Future<SettingsDto?> updateFlareSolverrTimeout(int value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateFlareSolverrTimeout(
          Options$Mutation$UpdateFlareSolverrTimeout(
            variables: Variables$Mutation$UpdateFlareSolverrTimeout(
              flareSolverrTimeout: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> updateFlareSolverrUrl(String value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateFlareSolverrUrl(
          Options$Mutation$UpdateFlareSolverrUrl(
            variables: Variables$Mutation$UpdateFlareSolverrUrl(
              flareSolverrUrl: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> toggleDebugLogs(bool value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$ToggleDebugLogs(
          Options$Mutation$ToggleDebugLogs(
            variables: Variables$Mutation$ToggleDebugLogs(
              debugLogsEnabled: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<SettingsDto?> toggleSystemTrayEnabled(bool value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$ToggleSystemTrayEnabled(
          Options$Mutation$ToggleSystemTrayEnabled(
            variables: Variables$Mutation$ToggleSystemTrayEnabled(
              systemTrayEnabled: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );
}

@riverpod
ServerSettingsRepository serverSettingsRepository(Ref ref) =>
    ServerSettingsRepository(
      ref.watch(graphQlClientProvider),
      permissions: ref.watch(accountPermissionGuardProvider),
    );
