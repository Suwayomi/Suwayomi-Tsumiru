// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../domain/filter/filter_model.dart';
import '../../domain/manga_page/manga_page.dart';
import '../../domain/source/source_model.dart';
import '../../domain/source_preference/source_preference.dart';
import 'graphql/__generated__/query.graphql.dart';

part 'source_repository.g.dart';

class SourceRepository {
  final GraphQLClient ferryClient;

  SourceRepository(this.ferryClient);

  Future<List<SourceDto>?> getSourceList() =>
      ferryClient.query$SourceList().getData((data) => data.sources.nodes);

  Future<MangaPage?> fetchSourceManga({
    required String sourceId,
    required SourceType sourceType,
    required int page,
    String? query,
    List<FilterChange>? filters,
  }) =>
      ferryClient
          .mutate$FetchSourceManga(
            Options$Mutation$FetchSourceManga(
              variables: Variables$Mutation$FetchSourceManga(
                input: Input$FetchSourceMangaInput(
                  query: query,
                  page: page,
                  source: sourceId,
                  type: sourceType,
                  filters: filters,
                ),
              ),
            ),
          )
          .getData((data) => data.fetchSourceManga);

  Future<SourceDto?> getSource(String sourceId) => ferryClient
      .query$SourceById(Options$Query$SourceById(
          variables: Variables$Query$SourceById(id: sourceId)))
      .getData((data) => data.source);

  Future<List<SourcePreference>?> getSourcePreference(String sourceId) =>
      ferryClient
          .query$SourcePreferenceById(Options$Query$SourcePreferenceById(
              variables: Variables$Query$SourcePreferenceById(id: sourceId),
              fetchPolicy: FetchPolicy.noCache))
          .getData((data) => data.source.preferences);

  Future<List<Filter>?> getSourceFilter(String sourceId) => ferryClient
      .query$SourceFilterById(Options$Query$SourceFilterById(
          variables: Variables$Query$SourceFilterById(id: sourceId)))
      .getData((data) => data.source.filters);

  Future<void> updateSourcePreferenceById(
          String sourceId, SourcePreferenceChange change) =>
      ferryClient
          .mutate$UpdateSourcePreference(
            Options$Mutation$UpdateSourcePreference(
              variables: Variables$Mutation$UpdateSourcePreference(
                input: Input$UpdateSourcePreferenceInput(
                  change: change,
                  source: sourceId,
                ),
              ),
            ),
          )
          .getData((data) => data.updateSourcePreference?.preferences);

  /// Pins/unpins a source by writing the `webUI_isPinned` server meta key
  /// (the exact key WebUI uses, so the state syncs across clients).
  Future<void> setSourcePinned(String sourceId, bool pinned) => ferryClient
      .mutate$SetSourceMeta(
        Options$Mutation$SetSourceMeta(
          variables: Variables$Mutation$SetSourceMeta(
            input: Input$SetSourceMetaInput(
              meta: Input$SourceMetaTypeInput(
                sourceId: sourceId,
                key: kSourcePinnedMetaKey,
                value: pinned ? 'true' : 'false',
              ),
            ),
          ),
        ),
      )
      .getData((data) => data.setSourceMeta?.meta);
}

@riverpod
SourceRepository sourceRepository(Ref ref) =>
    SourceRepository(ref.watch(graphQlClientProvider));
