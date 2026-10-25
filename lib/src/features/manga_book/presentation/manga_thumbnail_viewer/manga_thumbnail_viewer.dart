// Copyright (c) 2023 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:ui';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/cover_cache/cover_cache.dart';
import '../../../../widgets/server_image.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../domain/manga/manga_model.dart';
import '../manga_details/controller/manga_details_controller.dart';
import '../manga_details/widgets/edit_cover_picker.dart';

class MangaThumbnailViewer extends ConsumerWidget {
  const MangaThumbnailViewer({super.key, required this.manga});

  final MangaDto manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customCover = ref.watch(
      mangaCustomCoverProvider(mangaId: manga.id),
    );
    final custom = customCover?.trim();
    final hasCustom = custom != null && custom.isNotEmpty;
    final imageUrl = hasCustom ? custom : manga.thumbnailUrl ?? '';
    final coverVersion = hasCustom ? null : manga.thumbnailUrlLastFetched;
    final sessionCurrent = ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    bool current() => context.mounted && sessionCurrent();

    Future<File> resolveCoverFile() async {
      final request = serverImageRequest(
        ref,
        imageUrl,
        coverVersion: coverVersion,
      );
      if (request.localPath != null) return File(request.localPath!);
      // Display covers always live in the cover cache, as ServerImage files them.
      return ref
          .read(coverCacheManagerProvider)
          .getSingleFile(
            request.fetchUrl,
            key: request.cacheKey,
            headers: request.headers ?? const {},
          );
    }

    Future<void> shareCover() async {
      final toast = ref.read(toastProvider);
      final errorMsg = context.l10n.errorSomethingWentWrong;
      try {
        final file = await resolveCoverFile();
        if (!current()) return;
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)]),
        );
      } catch (_) {
        if (current()) toast?.showError(errorMsg, instantShow: true);
      }
    }

    Future<void> saveCover() async {
      final toast = ref.read(toastProvider);
      final errorMsg = context.l10n.errorSomethingWentWrong;
      final savedMsg = context.l10n.savedToGallery;
      try {
        final file = await resolveCoverFile();
        if (!current()) return;
        if (!await Gal.requestAccess()) {
          toast?.showError(errorMsg, instantShow: true);
          return;
        }
        if (!current()) return;
        await Gal.putImage(file.path);
        toast?.show(savedMsg, instantShow: true);
      } catch (_) {
        if (current()) toast?.showError(errorMsg, instantShow: true);
      }
    }

    Future<void> deleteCover(String previous) async {
      final updatedMsg = context.l10n.coverUpdated;
      final undoLabel = context.l10n.undo;
      await ref
          .read(mangaCustomCoverProvider(mangaId: manga.id).notifier)
          .clear();
      if (!current()) return;
      ref
          .read(toastProvider)
          ?.showWithAction(
            updatedMsg,
            actionLabel: undoLabel,
            onAction: () => ref
                .read(mangaCustomCoverProvider(mangaId: manga.id).notifier)
                .setCover(previous),
          );
    }

    final isMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => context.pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colorScheme.surface.withValues(alpha: 0.1),
                  ),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Center(
                      child: ServerImage(
                        imageUrl: imageUrl,
                        fallbackImageUrl: manga.thumbnailUrl,
                        coverVersion: coverVersion,
                        fallbackCoverVersion: manga.thumbnailUrlLastFetched,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  _ActionsPill(
                    children: [
                      IconButton(
                        tooltip: context.l10n.close,
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _ActionsPill(
                    children: [
                      if (isMobile) ...[
                        IconButton(
                          tooltip: context.l10n.share,
                          icon: const Icon(FluentIcons.share_24_regular),
                          onPressed: shareCover,
                        ),
                        IconButton(
                          tooltip: context.l10n.save,
                          icon: const Icon(FluentIcons.save_24_regular),
                          onPressed: saveCover,
                        ),
                      ],
                      if (manga.user.inLibrary)
                        if (hasCustom)
                          PopupMenuButton<String>(
                            tooltip: context.l10n.editCover,
                            icon: const Icon(FluentIcons.edit_24_regular),
                            onSelected: (value) {
                              if (value == 'edit') {
                                showEditCoverPicker(context, ref, manga);
                              } else {
                                deleteCover(custom);
                              }
                            },
                            itemBuilder: (menuContext) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(context.l10n.edit),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(context.l10n.delete),
                              ),
                            ],
                          )
                        else
                          IconButton(
                            tooltip: context.l10n.editCover,
                            icon: const Icon(FluentIcons.edit_24_regular),
                            onPressed: () =>
                                showEditCoverPicker(context, ref, manga),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsPill extends StatelessWidget {
  const _ActionsPill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: colors.secondaryContainer.withValues(alpha: 0.95),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: colors.onSecondaryContainer),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
