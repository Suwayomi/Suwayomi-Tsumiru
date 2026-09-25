import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../account/domain/account_access.dart';
import '../../../data/user_settings.dart';
import '../domain/koreader_sync_domain.dart';
import './graphql/__generated__/koreader_sync.graphql.dart';

part 'koreader_sync_repository.g.dart';

typedef KoSyncConnectResult = ({bool isLoggedIn, String? message});

class KoreaderSyncRepository {
  const KoreaderSyncRepository(
    this.ferryClient, {
    required this.routing,
    required this.updated,
  });

  final UserSettingsRouting routing;

  final GraphQLClient ferryClient;

  final void Function() updated;

  Future<KoSyncStatus> status() async {
    final status = await ferryClient
        .query$KoSyncStatus(
          Options$Query$KoSyncStatus(fetchPolicy: FetchPolicy.noCache),
        )
        .getData((data) => data.koSyncStatus);
    return status == null
        ? const KoSyncStatus(isLoggedIn: false)
        : KoSyncStatus(
            isLoggedIn: status.isLoggedIn,
            serverAddress: status.serverAddress,
            username: status.username,
          );
  }

  /// Null when the server predates KOReader Sync: the query itself is rejected.
  Future<Fragment$KoreaderSyncSettingsDto?> legacySettings() async {
    try {
      return await ferryClient
          .query$KoreaderSyncLegacySettings(
            Options$Query$KoreaderSyncLegacySettings(
              fetchPolicy: FetchPolicy.noCache,
            ),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<KoSyncConnectResult> connect({
    required String serverAddress,
    required String username,
    required String password,
  }) async {
    final payload = await ferryClient
        .mutate$ConnectKoSyncAccount(
          Options$Mutation$ConnectKoSyncAccount(
            fetchPolicy: FetchPolicy.noCache,
            variables: Variables$Mutation$ConnectKoSyncAccount(
              input: Input$ConnectKoSyncAccountInput(
                serverAddress: serverAddress,
                username: username,
                password: password,
              ),
            ),
          ),
        )
        .getData((data) => data.connectKoSyncAccount);
    if (payload == null) throw StateError('Missing KOReader Sync response');
    return (isLoggedIn: payload.status.isLoggedIn, message: payload.message);
  }

  /// Returns true when logout failed: the server reports the account still in.
  Future<bool> logout() async {
    final status = await ferryClient
        .mutate$LogoutKoSyncAccount(
          Options$Mutation$LogoutKoSyncAccount(
            fetchPolicy: FetchPolicy.noCache,
            variables: Variables$Mutation$LogoutKoSyncAccount(
              input: Input$LogoutKoSyncAccountInput(),
            ),
          ),
        )
        .getData((data) => data.logoutKoSyncAccount.status);
    return status?.isLoggedIn ?? false;
  }

  Future<bool> updateStrategyForward(Enum$KoreaderSyncConflictStrategy value) =>
      _write(
        Input$PartialUserSettingsTypeInput(koreaderSyncStrategyForward: value),
        () => _legacyWrite(
          ferryClient.mutate$UpdateKoreaderSyncStrategyForward(
            Options$Mutation$UpdateKoreaderSyncStrategyForward(
              variables: Variables$Mutation$UpdateKoreaderSyncStrategyForward(
                koreaderSyncStrategyForward: value,
              ),
            ),
          ),
        ),
      );

  Future<bool> updateStrategyBackward(
    Enum$KoreaderSyncConflictStrategy value,
  ) => _write(
    Input$PartialUserSettingsTypeInput(koreaderSyncStrategyBackward: value),
    () => _legacyWrite(
      ferryClient.mutate$UpdateKoreaderSyncStrategyBackward(
        Options$Mutation$UpdateKoreaderSyncStrategyBackward(
          variables: Variables$Mutation$UpdateKoreaderSyncStrategyBackward(
            koreaderSyncStrategyBackward: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> updateChecksumMethod(Enum$KoreaderSyncChecksumMethod value) =>
      _write(
        Input$PartialUserSettingsTypeInput(koreaderSyncChecksumMethod: value),
        () => _legacyWrite(
          ferryClient.mutate$UpdateKoreaderSyncChecksumMethod(
            Options$Mutation$UpdateKoreaderSyncChecksumMethod(
              variables: Variables$Mutation$UpdateKoreaderSyncChecksumMethod(
                koreaderSyncChecksumMethod: value,
              ),
            ),
          ),
        ),
      );

  Future<bool> updatePercentageTolerance(double value) => _write(
    Input$PartialUserSettingsTypeInput(koreaderSyncPercentageTolerance: value),
    () => _legacyWrite(
      ferryClient.mutate$UpdateKoreaderSyncPercentageTolerance(
        Options$Mutation$UpdateKoreaderSyncPercentageTolerance(
          variables: Variables$Mutation$UpdateKoreaderSyncPercentageTolerance(
            koreaderSyncPercentageTolerance: value,
          ),
        ),
      ),
    ),
  );

  Future<bool> _write(
    Input$PartialUserSettingsTypeInput patch,
    Future<void> Function() legacy,
  ) async {
    await routing.update(patch, () async {
      await legacy();
      return null;
    });
    updated();
    return true;
  }

  Future<void> _legacyWrite<T>(Future<QueryResult<T>> request) async {
    await request.getData((data) => data);
  }
}

@riverpod
KoreaderSyncRepository koreaderSyncRepository(Ref ref) =>
    KoreaderSyncRepository(
      ref.watch(graphQlClientProvider),
      routing: ref.watch(userSettingsRoutingProvider),
      updated: () => ref.invalidate(koreaderSyncSettingsProvider),
    );

@riverpod
Future<KoSyncStatus> koSyncStatus(Ref ref) =>
    ref.watch(koreaderSyncRepositoryProvider).status();

@riverpod
Future<KoreaderSyncSettings?> koreaderSyncSettings(Ref ref) async {
  switch (ref.watch(settledAccountAccessProvider).capability) {
    case AccountCapability.unknown:
      throw StateError('Account settings unavailable');
    case AccountCapability.supported:
      final user = await ref.watch(userSettingsProvider.future);
      if (user == null) throw StateError('Missing account settings');
      return (
        strategyForward: user.koreaderSyncStrategyForward,
        strategyBackward: user.koreaderSyncStrategyBackward,
        checksumMethod: user.koreaderSyncChecksumMethod,
        percentageTolerance: user.koreaderSyncPercentageTolerance,
      );
    case AccountCapability.unsupported:
      final settings = await ref
          .watch(koreaderSyncRepositoryProvider)
          .legacySettings();
      if (settings == null) return null;
      return (
        strategyForward: settings.koreaderSyncStrategyForward,
        strategyBackward: settings.koreaderSyncStrategyBackward,
        checksumMethod: settings.koreaderSyncChecksumMethod,
        percentageTolerance: settings.koreaderSyncPercentageTolerance,
      );
  }
}
