// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/cover_cache/cover_cache.dart';
import '../../../../widgets/server_image.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../domain/manga/manga_model.dart';
import '../manga_details/controller/manga_details_controller.dart';
import '../manga_details/widgets/edit_cover_picker.dart';
import 'manga_thumbnail_viewer.dart';

void openCoverViewer(BuildContext context, MangaDto manga) {
  if (context.windowSizeClass == WindowSizeClass.compact) {
    Navigator.push(
      context,
      PageRouteBuilder(
        fullscreenDialog: true,
        opaque: false,
        pageBuilder: (context, _, _) => MangaThumbnailViewer(manga: manga),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) {
              if (context.reduceMotion) {
                return ReducedRouteTransition(
                  animation: animation,
                  child: child,
                );
              }

              const begin = Offset(-1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.ease;

              final tween = Tween(begin: begin, end: end);
              final curvedAnimation = CurvedAnimation(
                parent: animation,
                curve: curve,
              );

              return SlideTransition(
                position: tween.animate(curvedAnimation),
                child: child,
              );
            },
      ),
    );
    return;
  }
  showDialog<void>(context: context, builder: (_) => _CoverDialog(manga: manga));
}

bool _isShareSavePlatform() =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<File> _resolveCoverFile(
  WidgetRef ref,
  String imageUrl,
  String? coverVersion,
) async {
  final request = serverImageRequest(ref, imageUrl, coverVersion: coverVersion);
  if (request.localPath != null) return File(request.localPath!);
  // Display covers always live in the cover cache, as ServerImage files them.
  return ref
      .read(coverCacheManagerProvider)
      .getSingleFile(
        request.fetchUrl,
        key: request.cacheKey,
        headers: request.headers ?? const {},
      )
      .catchError((Object err) async {
        if (coverVersion == null || coverVersion.isEmpty) throw err;
        final unversioned = serverImageRequest(ref, imageUrl);
        final cached = await ref
            .read(coverCacheManagerProvider)
            .getFileFromCache(unversioned.cacheKey);
        if (cached != null) return cached.file;
        throw err;
      });
}

Future<void> _shareCover(
  BuildContext context,
  WidgetRef ref,
  String imageUrl,
  String? coverVersion,
) async {
  final toast = ref.read(toastProvider);
  final errorMsg = context.l10n.errorSomethingWentWrong;
  final sessionCurrent = ref
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  bool current() => context.mounted && sessionCurrent();
  try {
    final file = await _resolveCoverFile(ref, imageUrl, coverVersion);
    if (!current()) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  } catch (_) {
    if (current()) toast?.showError(errorMsg);
  }
}

Future<void> _saveCover(
  BuildContext context,
  WidgetRef ref,
  String imageUrl,
  String? coverVersion,
) async {
  final toast = ref.read(toastProvider);
  final errorMsg = context.l10n.errorSomethingWentWrong;
  final savedMsg = context.l10n.savedToGallery;
  final sessionCurrent = ref
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  bool current() => context.mounted && sessionCurrent();
  try {
    final file = await _resolveCoverFile(ref, imageUrl, coverVersion);
    if (!current()) return;
    if (!await Gal.requestAccess()) {
      toast?.showError(errorMsg);
      return;
    }
    if (!current()) return;
    await Gal.putImage(file.path);
    toast?.show(savedMsg);
  } catch (_) {
    if (current()) toast?.showError(errorMsg);
  }
}

Future<void> _deleteCover(
  BuildContext context,
  WidgetRef ref,
  MangaDto manga,
  String previous,
) async {
  final container = ProviderScope.containerOf(context);
  final sessionCurrent = ref
      .read(authCredentialsStoreProvider.notifier)
      .captureSession();
  final updatedMsg = context.l10n.coverUpdated;
  final failedMsg = context.l10n.coverUpdateFailed;
  final undoLabel = context.l10n.undo;
  final cleared = await ref
      .read(mangaCustomCoverProvider(mangaId: manga.id).notifier)
      .clear();
  if (!context.mounted || !sessionCurrent()) return;
  if (!cleared) {
    ref.read(toastProvider)?.showError(failedMsg);
    return;
  }
  ref
      .read(toastProvider)
      ?.showWithAction(
        updatedMsg,
        actionLabel: undoLabel,
        overlayContext: context,
        onAction: () async {
          if (!sessionCurrent()) return;
          final restored = await container
              .read(mangaCustomCoverProvider(mangaId: manga.id).notifier)
              .setCover(previous);
          if (!sessionCurrent()) return;
          if (!restored) container.read(toastProvider)?.showError(failedMsg);
        },
      );
}

List<Widget> coverShareSaveButtons(
  BuildContext context,
  WidgetRef ref,
  String imageUrl,
  String? coverVersion,
) {
  if (!_isShareSavePlatform()) return const [];
  return [
    IconButton(
      tooltip: context.l10n.share,
      icon: const Icon(FluentIcons.share_24_regular),
      onPressed: () => _shareCover(context, ref, imageUrl, coverVersion),
    ),
    IconButton(
      tooltip: context.l10n.save,
      icon: const Icon(FluentIcons.save_24_regular),
      onPressed: () => _saveCover(context, ref, imageUrl, coverVersion),
    ),
  ];
}

Widget coverEditButton(
  BuildContext context,
  WidgetRef ref,
  MangaDto manga,
  String? custom,
) {
  if (custom == null) {
    return IconButton(
      tooltip: context.l10n.editCover,
      icon: const Icon(FluentIcons.edit_24_regular),
      onPressed: () => showEditCoverPicker(context, ref, manga),
    );
  }
  return PopupMenuButton<String>(
    tooltip: context.l10n.editCover,
    icon: const Icon(FluentIcons.edit_24_regular),
    onSelected: (value) {
      if (value == 'edit') {
        showEditCoverPicker(context, ref, manga);
      } else {
        _deleteCover(context, ref, manga, custom);
      }
    },
    itemBuilder: (menuContext) => [
      PopupMenuItem(value: 'edit', child: Text(context.l10n.edit)),
      PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
    ],
  );
}

class _CoverDialog extends ConsumerWidget {
  const _CoverDialog({required this.manga});

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

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                ),
                child: ClipRRect(
                  borderRadius: KBorderRadius.r12.radius,
                  child: ServerImage(
                    imageUrl: imageUrl,
                    fallbackImageUrl: manga.thumbnailUrl,
                    coverVersion: coverVersion,
                    fallbackCoverVersion: manga.thumbnailUrlLastFetched,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...coverShareSaveButtons(context, ref, imageUrl, coverVersion),
                if (manga.user.inLibrary)
                  coverEditButton(
                    context,
                    ref,
                    manga,
                    hasCustom ? custom : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
