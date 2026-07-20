// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import 'graphql/__generated__/query.graphql.dart';

part 'tracker_repository.g.dart';

class TrackerRepository {
  const TrackerRepository(this.client);
  final GraphQLClient client;

  Future<List<Fragment$TrackerDto>?> getTrackers() => client
      .query$GetTrackers(Options$Query$GetTrackers())
      .getData((data) => data.trackers.nodes);

  Future<void> loginOAuth({
    required int trackerId,
    required String callbackUrl,
  }) =>
      client
          .mutate$TrackerLoginOAuth(
            Options$Mutation$TrackerLoginOAuth(
              variables: Variables$Mutation$TrackerLoginOAuth(
                trackerId: trackerId,
                callbackUrl: callbackUrl,
              ),
            ),
          )
          .getData((d) => d);

  Future<void> loginCredentials({
    required int trackerId,
    required String username,
    required String password,
  }) =>
      client
          .mutate$TrackerLoginCredentials(
            Options$Mutation$TrackerLoginCredentials(
              variables: Variables$Mutation$TrackerLoginCredentials(
                trackerId: trackerId,
                username: username,
                password: password,
              ),
            ),
          )
          .getData((d) => d);

  Future<void> logout(int trackerId) => client
      .mutate$TrackerLogout(
        Options$Mutation$TrackerLogout(
          variables: Variables$Mutation$TrackerLogout(trackerId: trackerId),
        ),
      )
      .getData((d) => d);

  Future<List<Fragment$TrackSearchDto>?> search({
    required int trackerId,
    required String query,
  }) =>
      client
          .query$SearchTracker(
            Options$Query$SearchTracker(
              variables: Variables$Query$SearchTracker(
                trackerId: trackerId,
                query: query,
              ),
            ),
          )
          .getData((data) => data.searchTracker.trackSearches);

  Future<void> bind({
    required int mangaId,
    required int trackerId,
    required String remoteId,
    required bool private,
  }) async {
    final data = await client
        .mutate$BindTrack(
          Options$Mutation$BindTrack(
            variables: Variables$Mutation$BindTrack(
              mangaId: mangaId,
              trackerId: trackerId,
              remoteId: remoteId,
              private: private,
            ),
          ),
        )
        .getData((d) => d);
    // A null payload (no exception, but nothing bound) must surface as an error
    // so callers don't treat an unbound record as success.
    if (data == null) {
      throw Exception('Tracking bind returned no data');
    }
  }

  Future<void> update({
    required int recordId,
    int? status,
    String? scoreString,
    double? lastChapterRead,
    String? startDate,
    String? finishDate,
    bool? private,
  }) =>
      client
          .mutate$UpdateTrack(
            Options$Mutation$UpdateTrack(
              variables: Variables$Mutation$UpdateTrack(
                input: Input$UpdateTrackInput(
                  recordId: recordId,
                  status: status,
                  scoreString: scoreString,
                  lastChapterRead: lastChapterRead,
                  startDate: startDate,
                  finishDate: finishDate,
                  private: private,
                ),
              ),
            ),
          )
          .getData((d) => d);

  Future<void> unbind({
    required int recordId,
    bool? deleteRemoteTrack,
  }) =>
      client
          .mutate$UnbindTrack(
            Options$Mutation$UnbindTrack(
              variables: Variables$Mutation$UnbindTrack(
                recordId: recordId,
                deleteRemoteTrack: deleteRemoteTrack,
              ),
            ),
          )
          .getData((d) => d);

  Future<void> fetch(int recordId) => client
      .mutate$FetchTrack(
        Options$Mutation$FetchTrack(
          variables: Variables$Mutation$FetchTrack(recordId: recordId),
        ),
      )
      .getData((d) => d);

  Future<void> trackProgress(int mangaId) => client
      .mutate$TrackProgress(
        Options$Mutation$TrackProgress(
          variables: Variables$Mutation$TrackProgress(mangaId: mangaId),
        ),
      )
      .getData((d) => d);

  Future<List<Fragment$TrackRecordDto>?> getMangaTrackRecords(
    int mangaId,
  ) =>
      client
          .query$GetMangaTrackRecords(
            Options$Query$GetMangaTrackRecords(
              variables: Variables$Query$GetMangaTrackRecords(
                mangaId: mangaId,
              ),
            ),
          )
          .getData((data) => data.manga.trackRecords.nodes);
}

@riverpod
TrackerRepository trackerRepository(Ref ref) =>
    TrackerRepository(ref.watch(graphQlClientProvider));

@riverpod
Future<List<Fragment$TrackerDto>> trackers(Ref ref) async {
  final repo = ref.watch(trackerRepositoryProvider);
  return await repo.getTrackers() ?? [];
}

/// The subset of [trackers] where [Fragment$TrackerDto.isLoggedIn] is true.
///
/// UI surfaces gated on this: tracker-score sort, per-tracker filter,
/// by-track-status group. When the list is empty those surfaces stay hidden.
@riverpod
Future<List<Fragment$TrackerDto>> loggedInTrackers(Ref ref) async {
  final all = await ref.watch(trackersProvider.future);
  return all.where((t) => t.isLoggedIn).toList();
}
