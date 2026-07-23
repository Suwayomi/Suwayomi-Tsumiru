import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../domain/settings/settings.dart';
import './graphql/__generated__/query.graphql.dart';

part 'browse_settings_repository.g.dart';

class BrowseSettingsRepository {
  const BrowseSettingsRepository(this.ferryClient);

  final GraphQLClient ferryClient;

  Future<SettingsDto?> updateSourceInParallel(int maxSourcesInParallel) =>
      ferryClient
          .mutate$UpdateSourceInParallel(
            Options$Mutation$UpdateSourceInParallel(
              variables: Variables$Mutation$UpdateSourceInParallel(
                  maxSourcesInParallel: maxSourcesInParallel),
            ),
          )
          .getData((data) => data.setSettings.settings);

  /// Legacy repo write. Servers >= v2.3.2223 removed `extensionRepos` from
  /// PartialSettingsTypeInput, so this document can't live in codegen against
  /// the current schema; it only ever runs against pre-store servers.
  static const updateExtensionReposDocument = r'''
    mutation UpdateExtensionRepos($extensionRepos: [String!]!) {
      setSettings(input: {settings: {extensionRepos: $extensionRepos}}) {
        clientMutationId
      }
    }
  ''';

  Future<void> updateExtensionRepos(Set<String> extensionRepos) async {
    final result = await ferryClient.mutate(
      MutationOptions(
        document: gql(updateExtensionReposDocument),
        variables: {'extensionRepos': extensionRepos.toList()},
      ),
    );
    if (result.hasException) throw result.exception!;
  }

  Future<SettingsDto?> updateLocalSourcePath(String value) => ferryClient
      .mutate$UpdateLocalSourcePath(
        Options$Mutation$UpdateLocalSourcePath(
          variables: Variables$Mutation$UpdateLocalSourcePath(
            localSourcePath: value,
          ),
        ),
      )
      .getData((data) => data.setSettings.settings);
}

@riverpod
BrowseSettingsRepository browseSettingsRepository(Ref ref) =>
    BrowseSettingsRepository(ref.watch(graphQlClientProvider));
