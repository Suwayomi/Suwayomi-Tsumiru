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
import '../../../account/data/account_permission.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../../offline/data/offline_download_permission.dart';
import '../../domain/downloads/downloads_model.dart';
import '../../domain/downloads_queue/downloads_queue_model.dart';
import './graphql/__generated__/query.graphql.dart';

part 'downloads_repository.g.dart';

class DownloadsRepository {
  const DownloadsRepository(
    this.client,
    this.subscriptionClient, {
    required this.permissions,
    this.verifyBeforeEnqueue,
  });
  final AccountPermissionGuard permissions;
  final Future<void> Function()? verifyBeforeEnqueue;

  final GraphQLClient client;
  final GraphQLClient subscriptionClient;
  // Downloads
  Future<void> startDownloads() => permissions.run(
    Enum$UserPermission.DOWNLOAD_CHAPTERS,
    () => client
        .mutate$StartDownloader(
          Options$Mutation$StartDownloader(
            variables: Variables$Mutation$StartDownloader(
              input: Input$StartDownloaderInput(),
            ),
          ),
        )
        .getData((data) {}),
  );

  Future<void> stopDownloads() => permissions.run(
    Enum$UserPermission.DOWNLOAD_CHAPTERS,
    () => client
        .mutate$StopDownloader(
          Options$Mutation$StopDownloader(
            variables: Variables$Mutation$StopDownloader(
              input: Input$StopDownloaderInput(),
            ),
          ),
        )
        .getData((data) {}),
  );
  Future<void> clearDownloads() => permissions.run(
    Enum$UserPermission.DOWNLOAD_CHAPTERS,
    () => client
        .mutate$ClearDownloader(
          Options$Mutation$ClearDownloader(
            variables: Variables$Mutation$ClearDownloader(
              input: Input$ClearDownloaderInput(),
            ),
          ),
        )
        .getData((data) {}),
  );

  Future<void> addChaptersBatchToDownloadQueue(List<int> chapterIds) async {
    await verifyBeforeEnqueue?.call();
    return permissions.run(
      Enum$UserPermission.DOWNLOAD_CHAPTERS,
      () => client
          .mutate$EnqueueChapterDownloads(
            Options$Mutation$EnqueueChapterDownloads(
              variables: Variables$Mutation$EnqueueChapterDownloads(
                input: Input$EnqueueChapterDownloadsInput(ids: chapterIds),
              ),
            ),
          )
          .then((response) {
            if (response.result?.enqueueChapterDownloads == null) {
              throw StateError(
                'The server did not accept the download request',
              );
            }
          }),
    );
  }

  Future<void> removeChapterFromDownloadQueue(int chapterId) => permissions.run(
    Enum$UserPermission.DOWNLOAD_CHAPTERS,
    () => client
        .mutate$DequeueChapterDownloads(
          Options$Mutation$DequeueChapterDownloads(
            variables: Variables$Mutation$DequeueChapterDownloads(
              input: Input$DequeueChapterDownloadInput(id: chapterId),
            ),
          ),
        )
        .getData((data) {}),
  );

  Future<DownloadStatusDto?> reorderDownload(int chapterId, int to) =>
      permissions.run(
        Enum$UserPermission.DOWNLOAD_CHAPTERS,
        () => client
            .mutate$ReorderChapterDownload(
              Options$Mutation$ReorderChapterDownload(
                variables: Variables$Mutation$ReorderChapterDownload(
                  input: Input$ReorderChapterDownloadInput(
                    chapterId: chapterId,
                    to: to,
                  ),
                ),
              ),
            )
            .getData((data) => data.reorderChapterDownload?.downloadStatus),
      );

  Stream<DownloadUpdatesDto?> downloadStatusSubscription() => subscriptionClient
      .subscribe$DownloadStatusChanged(
        Options$Subscription$DownloadStatusChanged(
          variables: Variables$Subscription$DownloadStatusChanged(
            input: Input$DownloadChangedInput(maxUpdates: 150),
          ),
        ),
      )
      .getData((data) => data.downloadStatusChanged);

  Future<DownloadStatusDto?> getDownloadStatus() =>
      client.query$GetDownloadStatus().getData((data) => data.downloadStatus);
}

@riverpod
DownloadsRepository downloadsRepository(Ref ref) {
  final current = watchAuthSession(ref);
  final read = ref.container.read;
  return DownloadsRepository(
    ref.watch(graphQlClientProvider),
    ref.watch(graphQlSubscriptionClientProvider),
    permissions: ref.watch(accountPermissionGuardProvider),
    verifyBeforeEnqueue: () async {
      if (!current()) throw StateError('Authentication session changed');
      await verifyDownloadPermission(read);
      if (!current()) throw StateError('Authentication session changed');
    },
  );
}
