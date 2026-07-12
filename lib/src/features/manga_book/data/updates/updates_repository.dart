// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../domain/chapter_page/chapter_page_model.dart';
import '../../domain/update_status/update_status_model.dart';
import './graphql/__generated__/query.graphql.dart';

part 'updates_repository.g.dart';

class UpdatesRepository {
  const UpdatesRepository(this.client, this.subscriptionClient);

  final GraphQLClient client;
  final GraphQLClient subscriptionClient;
  // Downloads

  // Updates
  Future<ChapterPageWithMangaDto?> getRecentChaptersPage({
    int pageNo = 0,
  }) =>
      client
          .query$GetChapterWithMangaPage(
            Options$Query$GetChapterWithMangaPage(
              variables: Variables$Query$GetChapterWithMangaPage(
                filter: Input$ChapterFilterInput(
                  inLibrary: Input$BooleanFilterInput(equalTo: true),
                ),
                first: 50,
                offset: pageNo * 30,
                order: [
                  Input$ChapterOrderInput(
                    by: Enum$ChapterOrderBy.FETCHED_AT,
                    byType: Enum$SortOrder.DESC,
                  ),
                  Input$ChapterOrderInput(
                    by: Enum$ChapterOrderBy.SOURCE_ORDER,
                    byType: Enum$SortOrder.DESC,
                  ),
                ],
              ),
            ),
          )
          .getData((data) => data.chapters);

  Future<void> fetchUpdates({
    int? categoryId,
  }) async {
    if (categoryId != null) {
      await client.mutate$UpdateCategoryMangas(
        Options$Mutation$UpdateCategoryMangas(
          variables: Variables$Mutation$UpdateCategoryMangas(
            input: Input$UpdateCategoryMangaInput(categories: [categoryId]),
          ),
        ),
      );
    } else {
      await client.mutate$UpdateLibraryMangas(
        Options$Mutation$UpdateLibraryMangas(
          variables: Variables$Mutation$UpdateLibraryMangas(
            input: Input$UpdateLibraryMangaInput(),
          ),
        ),
      );
    }
  }

  Future<void> stopUpdates() => client.mutate$StopCategoryUpdate(
        Options$Mutation$StopCategoryUpdate(
          variables: Variables$Mutation$StopCategoryUpdate(
            input: Input$UpdateStopInput(),
          ),
        ),
      );

  Future<UpdateStatusDto?> summaryUpdates() async => client
      .query$UpdateStatusDto(Options$Query$UpdateStatusDto())
      .getData((data) => data.updateStatus);

  /// Cheap "is a run in progress" read, decoupled from the heavy job lists
  /// (see [updateRunningSubscription]).
  Future<bool?> runningSummary() async => client
      .query$UpdateRunningStatus(Options$Query$UpdateRunningStatus())
      .getData((data) => data.updateStatus.isRunning);

  /// Epoch-millis (as a string) of the last global library update, or null.
  Future<String?> lastUpdateTimestamp() async => client
      .query$LastUpdateTimestamp(Options$Query$LastUpdateTimestamp())
      .getData((data) => data.lastUpdateTimestamp.timestamp);

  Stream<UpdateStatusDto?> updateStatusSubscription() => subscriptionClient
      .subscribe$UpdateStatusChange(Options$Subscription$UpdateStatusChange())
      .getData((data) => data.updateStatusChanged);

  /// Running-only live signal. Requesting just `isRunning` keeps each pushed
  /// frame tiny, so it arrives promptly even mid-update when the full-status
  /// feed ([updateStatusSubscription]) stalls on the server's job-list
  /// resolvers. The banner's visibility rides on this, not the heavy feed.
  Stream<bool?> updateRunningSubscription() => subscriptionClient
      .subscribe$UpdateRunningChange(Options$Subscription$UpdateRunningChange())
      .getData((data) => data.updateStatusChanged.isRunning);
}

@riverpod
UpdatesRepository updatesRepository(Ref ref) => UpdatesRepository(
    ref.watch(graphQlClientProvider),
    ref.watch(graphQlSubscriptionClientProvider));

@riverpod
Future<UpdateStatusDto?> updateSummary(Ref ref) =>
    ref.watch(updatesRepositoryProvider).summaryUpdates();

@riverpod
Future<String?> libraryLastUpdated(Ref ref) =>
    ref.watch(updatesRepositoryProvider).lastUpdateTimestamp();

@riverpod
Stream<UpdateStatusDto?> updatesSocket(Ref ref) =>
    ref.watch(updatesRepositoryProvider).updateStatusSubscription();

@riverpod
Future<bool?> updateRunningSummary(Ref ref) =>
    ref.watch(updatesRepositoryProvider).runningSummary();

@riverpod
Stream<bool?> updateRunningSocket(Ref ref) =>
    ref.watch(updatesRepositoryProvider).updateRunningSubscription();
