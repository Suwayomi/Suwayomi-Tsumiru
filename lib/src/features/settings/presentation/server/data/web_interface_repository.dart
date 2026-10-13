import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../account/data/account_permission.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../account/domain/account_access.dart';
import 'graphql/__generated__/web_interface.graphql.dart';

List<Enum$WebUIFlavor> supportedWebInterfaceFlavors(Iterable<String> names) =>
    Enum$WebUIFlavor.values
        .where((flavor) => flavor != Enum$WebUIFlavor.$unknown)
        .where((flavor) => names.contains(flavor.name))
        .toList();

bool isServerWebInterface(String? serverUrl, Uri pageBase) {
  final server = Uri.tryParse(serverUrl ?? '');
  if (server == null || !server.hasAuthority || !pageBase.hasAuthority) {
    return false;
  }
  String path(Uri uri) => uri.path.replaceFirst(RegExp(r'/+$'), '');
  return server.origin == pageBase.origin && path(server) == path(pageBase);
}

class WebInterfaceRepository {
  const WebInterfaceRepository(this.client, {required this.permissions});

  final GraphQLClient client;
  final AccountPermissionGuard permissions;

  Future<Fragment$WebInterfaceSettingsDto?> settings() async {
    try {
      return await client
          .query$WebInterfaceSettings(
            Options$Query$WebInterfaceSettings(
              fetchPolicy: FetchPolicy.noCache,
            ),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<List<Enum$WebUIFlavor>> flavors() async {
    final result = await client.query(
      QueryOptions(
        document: gql('''
          query SupportedWebInterfaceFlavors {
            __type(name: "WebUIFlavor") { enumValues { name } }
          }
        '''),
        fetchPolicy: FetchPolicy.noCache,
      ),
    );
    if (result.hasException) throw OperationMessageException(result.exception!);
    final values = result.data?['__type']?['enumValues'] as List<dynamic>?;
    if (values == null) throw StateError('Missing WebUIFlavor capabilities');
    return supportedWebInterfaceFlavors(
      values.map((value) => value['name'] as String),
    );
  }

  Future<Fragment$WebInterfaceSettingsDto?> write(
    Input$PartialSettingsTypeInput patch,
  ) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => client
        .mutate$SetWebInterfaceSettings(
          Options$Mutation$SetWebInterfaceSettings(
            variables: Variables$Mutation$SetWebInterfaceSettings(
              settings: patch,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<Query$InstalledWebInterface$aboutWebUI?> installed() => client
      .query$InstalledWebInterface(
        Options$Query$InstalledWebInterface(fetchPolicy: FetchPolicy.noCache),
      )
      .getData((data) => data.aboutWebUI);

  Future<Query$CheckWebInterfaceUpdate$checkForWebUIUpdate?> check() => client
      .query$CheckWebInterfaceUpdate(
        Options$Query$CheckWebInterfaceUpdate(fetchPolicy: FetchPolicy.noCache),
      )
      .getData((data) => data.checkForWebUIUpdate);

  Future<Fragment$WebInterfaceUpdateStatusDto?> status() => client
      .query$WebInterfaceUpdateStatus(
        Options$Query$WebInterfaceUpdateStatus(
          fetchPolicy: FetchPolicy.noCache,
        ),
      )
      .getData((data) => data.getWebUIUpdateStatus);

  Future<Fragment$WebInterfaceUpdateStatusDto?> install() => client
      .mutate$InstallWebInterfaceUpdate(
        Options$Mutation$InstallWebInterfaceUpdate(
          fetchPolicy: FetchPolicy.noCache,
        ),
      )
      .getData((data) => data.updateWebUI?.updateStatus);
}

final webInterfaceRepositoryProvider = Provider<WebInterfaceRepository>(
  (ref) => WebInterfaceRepository(
    ref.watch(graphQlClientProvider),
    permissions: ref.watch(accountPermissionGuardProvider),
  ),
);

final webInterfaceSettingsProvider =
    FutureProvider.autoDispose<Fragment$WebInterfaceSettingsDto?>((ref) {
      if (!ref
          .watch(settledAccountAccessProvider)
          .allows(Enum$UserPermission.MANAGE_SETTINGS)) {
        return null;
      }
      return ref.watch(webInterfaceRepositoryProvider).settings();
    });

final webInterfaceFlavorsProvider =
    FutureProvider.autoDispose<List<Enum$WebUIFlavor>>(
      (ref) => ref.watch(webInterfaceRepositoryProvider).flavors(),
    );

final installedWebInterfaceProvider =
    FutureProvider.autoDispose<Query$InstalledWebInterface$aboutWebUI?>((ref) {
      if (ref.watch(settledAccountAccessProvider).capability ==
          AccountCapability.unknown) {
        return null;
      }
      return ref.watch(webInterfaceRepositoryProvider).installed();
    });
