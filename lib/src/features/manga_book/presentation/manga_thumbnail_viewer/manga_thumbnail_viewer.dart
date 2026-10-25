// Copyright (c) 2023 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/server_image.dart';
import '../../domain/manga/manga_model.dart';
import '../manga_details/controller/manga_details_controller.dart';
import 'cover_viewer.dart';

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
    final mediaButtons =
        coverShareSaveButtons(context, ref, imageUrl, coverVersion);
    final editButton = manga.user.inLibrary
        ? coverEditButton(context, ref, manga, hasCustom ? custom : null)
        : null;

    return Scaffold(
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
                  const Spacer(),
                  _ActionsPill(
                    children: [
                      IconButton(
                        tooltip: context.l10n.close,
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: () => context.pop(),
                      ),
                      ...mediaButtons,
                      ?editButton,
                    ],
                  ),
                  const Spacer(),
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
