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
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter_page/chapter_page_model.dart';
import '../../domain/manga/manga_model.dart';
import '../../domain/update_status/update_status_model.dart';
import '../../domain/updates/updates_filter.dart';
import './graphql/__generated__/query.graphql.dart';

part 'updates_repository.g.dart';

/// Rows per page. The offset step must match, or pages overlap and the list
/// repeats rows.
const int updatesPageSize = 50;

/// One page of the Updates feed: at most [updatesPageSize] chapters, newest
/// first, and whether another page follows.
typedef UpdatesPage = ({List<ChapterWithMangaDto> nodes, bool hasNextPage});

/// Splits a window fetched as [pageSize] + 1 rows into the page and whether
/// another one follows.
({List<T> nodes, bool hasNextPage}) splitPageWindow<T>(
  List<T> window,
  int pageSize,
) => (
  nodes: window.take(pageSize).toList(),
  hasNextPage: window.length > pageSize,
);

Input$BooleanFilterInput? _equals(bool? value) =>
    value == null ? null : Input$BooleanFilterInput(equalTo: value);

Input$ChapterFilterInput updatesFilterInput(UpdatesFilter filter) =>
    Input$ChapterFilterInput(
      inLibrary: Input$BooleanFilterInput(equalTo: true),
      isDownloaded: _equals(filter.downloaded),
      isRead: filter.unread == null ? null : _equals(!filter.unread!),
      isBookmarked: _equals(filter.bookmarked),
      // Komikku treats a finished chapter as neither started nor not-started, so
      // both sides of this filter also require unread (updatesView.sq).
      and: filter.started == null
          ? null
          : [
              Input$ChapterFilterInput(isRead: _equals(false)),
              Input$ChapterFilterInput(
                lastPageRead: filter.started!
                    ? Input$IntFilterInput(greaterThan: 0)
                    : Input$IntFilterInput(equalTo: 0),
              ),
            ],
    );

class UpdatesRepository {
  const UpdatesRepository(this.client, this.subscriptionClient);

  final GraphQLClient client;
  final GraphQLClient subscriptionClient;
  // Downloads

  // Updates

  /// Asks for one row more than a page rather than for `pageInfo` or
  /// `totalCount`: those cost the server a COUNT and two sorted lookups over
  /// every matching chapter on each request, where the extra row alone says
  /// whether another page follows. That leaves one query per page.
  Future<UpdatesPage?> getRecentChaptersPage({
    int pageNo = 0,
    UpdatesFilter filter = kNoUpdatesFilter,
  }) async {
    final page = await _getRecentChaptersWindow(pageNo, filter);
    return page == null ? null : splitPageWindow(page.nodes, updatesPageSize);
  }

  Future<ChapterPageWithMangaDto?> _getRecentChaptersWindow(
    int pageNo,
    UpdatesFilter filter,
  ) =>
      client
          .query$GetChapterWithMangaPage(
            Options$Query$GetChapterWithMangaPage(
              variables: Variables$Query$GetChapterWithMangaPage(
                filter: updatesFilterInput(filter),
                first: updatesPageSize + 1,
                offset: pageNo * updatesPageSize,
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

  /// The current run's progress, read once. See [updateProgressSubscription].
  Future<UpdateProgressDto?> updateProgress() async => client
      .query$UpdateProgress(Options$Query$UpdateProgress())
      .getData((data) => data.libraryUpdateStatus.jobsInfo);

  /// Series that failed in the most recent run. Reads the server's current
  /// status API — the deprecated `updateStatus` job lists hang on a live
  /// server, which is what left the old summary screen spinning.
  Future<List<MangaDto>> failedUpdates() async =>
      (await client
          .query$LibraryUpdateFailures(Options$Query$LibraryUpdateFailures())
          .getData((data) => [
                for (final update in data.libraryUpdateStatus.mangaUpdates)
                  if (update.status == Enum$MangaJobStatus.FAILED) update.manga,
              ])) ??
      const [];

  /// How many series failed in the most recent run, without fetching them.
  Future<int?> failedUpdateCount() async => client
      .query$LibraryUpdateFailureCount(
        Options$Query$LibraryUpdateFailureCount(),
      )
      .getData(
        (data) => data.libraryUpdateStatus.mangaUpdates
            .where((update) => update.status == Enum$MangaJobStatus.FAILED)
            .length,
      );

  /// Epoch-millis (as a string) of the last global library update, or null.
  Future<String?> lastUpdateTimestamp() async => client
      .query$LastUpdateTimestamp(Options$Query$LastUpdateTimestamp())
      .getData((data) => data.lastUpdateTimestamp.timestamp);

  /// Live progress of library updates: whether one runs and how far it got,
  /// pushed at most once a second. The server keeps these counts in memory,
  /// so a push costs it no query, however large the library.
  Stream<UpdateProgressDto?> updateProgressSubscription() => subscriptionClient
      .subscribe$UpdateProgressChange(
        Options$Subscription$UpdateProgressChange(),
      )
      .getData((data) => data.libraryUpdateStatusChanged.jobsInfo);
}

@riverpod
UpdatesRepository updatesRepository(Ref ref) => UpdatesRepository(
    ref.watch(graphQlClientProvider),
    ref.watch(graphQlSubscriptionClientProvider));

/// One-shot read of [updateProgressSocketProvider]'s data, for when the
/// socket is down or hasn't delivered yet.
@riverpod
Future<UpdateProgressDto?> updateProgressSummary(Ref ref) =>
    ref.watch(updatesRepositoryProvider).updateProgress();

@riverpod
Future<String?> libraryLastUpdated(Ref ref) =>
    ref.watch(updatesRepositoryProvider).lastUpdateTimestamp();

/// The single live progress subscription. Everything that follows a run reads
/// it, directly or through [updateRunningSocketProvider], so the server runs
/// one subscription per app instead of one per feature.
@riverpod
Stream<UpdateProgressDto?> updateProgressSocket(Ref ref) =>
    ref.watch(updatesRepositoryProvider).updateProgressSubscription();

/// Whether a library update is running, off [updateProgressSocketProvider].
/// Changes only when that does: progress is pushed every second during a
/// run, and listeners here act on the running edges.
@riverpod
AsyncValue<bool?> updateRunningSocket(Ref ref) => ref.watch(
  updateProgressSocketProvider.select(
    (progress) => progress.whenData((value) => value?.isRunning),
  ),
);

@riverpod
Future<List<MangaDto>> failedUpdates(Ref ref) =>
    ref.watch(updatesRepositoryProvider).failedUpdates();

/// For badges and menu labels; [failedUpdatesProvider] is for the errors list.
@riverpod
Future<int> failedUpdateCount(Ref ref) async =>
    await ref.watch(updatesRepositoryProvider).failedUpdateCount() ?? 0;
