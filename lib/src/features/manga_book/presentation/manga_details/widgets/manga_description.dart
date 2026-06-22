// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../offline/presentation/series_offline_button.dart';
import '../../../domain/manga/manga_model.dart';

class MangaDescription extends HookConsumerWidget {
  const MangaDescription({
    super.key,
    required this.manga,
    required this.removeMangaFromLibrary,
    required this.addMangaToLibrary,
    required this.refresh,
  });
  final MangaDto manga;
  final AsyncCallback refresh;
  final AsyncCallback removeMangaFromLibrary;
  final AsyncCallback addMangaToLibrary;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpanded = useState(context.isTablet);
    final cs = context.theme.colorScheme;
    final surface = context.theme.scaffoldBackgroundColor;
    final inLibrary = manga.inLibrary.ifNull();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Immersive hero: blurred cover backdrop + accent tint, fading into the
        // scaffold. Sits behind the cover/title block; no app-bar restructure.
        Stack(
          children: [
            if (manga.thumbnailUrl.isNotBlank)
              Positioned.fill(
                child: ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: ServerImage(
                      imageUrl: manga.thumbnailUrl ?? "",
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary.withValues(alpha: 0.30),
                      surface.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      surface.withValues(alpha: 0.10),
                      surface.withValues(alpha: 0.70),
                      surface,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              // Clear the transparent app bar (status bar + toolbar) so the
              // cover/title sit below the icons while the backdrop fills behind.
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + kToolbarHeight,
              ),
              child: MangaCoverDescriptiveListTile(
                manga: manga,
                showBadges: false,
                onTitleClicked: (query) =>
                    GlobalSearchRoute(query: query).push(context),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: BrandButton(
                  icon: Icon(
                    inLibrary
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                  label: Text(
                    inLibrary ? context.l10n.inLibrary : context.l10n.addToLibrary,
                  ),
                  onPressed: () async {
                    final val = await AsyncValue.guard(() async {
                      if (inLibrary) {
                        await removeMangaFromLibrary();
                      } else {
                        await addMangaToLibrary();
                      }
                      await refresh();
                    });
                    if (context.mounted) {
                      val.showToastOnError(ref.read(toastProvider));
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: SeriesOfflineButton(mangaId: manga.id)),
              if (manga.realUrl.isNotBlank) ...[
                const SizedBox(width: 10),
                BrandCircleButton(
                  icon: Icons.public_rounded,
                  onPressed: () => launchUrlInWeb(
                    context,
                    (manga.realUrl ?? ""),
                    ref.read(toastProvider),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (manga.description.isNotBlank)
          Padding(
            padding: KEdgeInsets.a16.size,
            child: Stack(
              alignment: AlignmentDirectional.bottomStart,
              children: [
                Text(
                  "${manga.description}\n",
                  maxLines: isExpanded.value ? null : 3,
                ),
                InkWell(
                  child: Container(
                    margin: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color:
                              context.theme.canvasColor.withValues(alpha: .7),
                        ),
                      ],
                      gradient: LinearGradient(
                        colors: [
                          context.theme.canvasColor.withValues(alpha: 0),
                          context.theme.canvasColor.withValues(alpha: .3),
                          context.theme.canvasColor.withValues(alpha: .5),
                          context.theme.canvasColor.withValues(alpha: .6),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        isExpanded.value
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                    ),
                  ),
                  onTap: () => isExpanded.value = (!isExpanded.value),
                ),
              ],
            ),
          ),
        if (isExpanded.value)
          Padding(
            padding: KEdgeInsets.h16.size,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...manga.genre.map<Widget>((e) => BrandChip(label: e)),
              ],
            ),
          )
        else
          Padding(
            padding: KEdgeInsets.h16.size,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...manga.genre.map<Widget>(
                    (e) => Padding(
                      padding: KEdgeInsets.h4.size,
                      child: BrandChip(label: e),
                    ),
                  )
                ],
              ),
            ),
          ),
      ],
    );
  }
}
