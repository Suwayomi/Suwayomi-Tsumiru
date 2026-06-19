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
import '../../../../../widgets/async_buttons/async_text_button_icon.dart';
import '../../../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../../../widgets/server_image.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            Positioned.fill(child: _CoverBackdrop(manga: manga)),
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + kToolbarHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MangaCoverDescriptiveListTile(
                    manga: manga,
                    showBadges: false,
                    onTitleClicked: (query) =>
                        GlobalSearchRoute(query: query).push(context),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        AsyncTextButtonIcon(
                          onPressed: () async {
                            final val = await AsyncValue.guard(() async {
                              if (manga.inLibrary.ifNull()) {
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
                          isPrimary: manga.inLibrary.ifNull(),
                          primaryIcon: const Icon(Icons.favorite_rounded),
                          secondaryIcon:
                              const Icon(Icons.favorite_border_outlined),
                          secondaryStyle: TextButton.styleFrom(
                              foregroundColor: Colors.grey),
                          primaryLabel: Text(context.l10n.inLibrary),
                          secondaryLabel: Text(context.l10n.addToLibrary),
                        ),
                        if (manga.realUrl.isNotBlank)
                          TextButton.icon(
                            onPressed: () async {
                              launchUrlInWeb(
                                context,
                                (manga.realUrl ?? ""),
                                ref.read(toastProvider),
                              );
                            },
                            icon: const Icon(Icons.public_rounded),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.grey),
                            label: Text(context.l10n.webView),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              // alignment: WrapAlignment.spaceBetween,
              children: [
                ...manga.genre.map<Widget>(
                  (e) => _GenreChip(e),
                )
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
                      child: _GenreChip(e),
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

/// Blurred, faded cover-art glow behind the manga-detail header (Komikku-style
/// hero). The cover fills the header, is blurred + dimmed, then a vertical
/// gradient fades it into the page surface so it blends into the chapter list.
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.manga});

  final MangaDto manga;

  @override
  Widget build(BuildContext context) {
    final url = manga.thumbnailUrl ?? '';
    if (url.isEmpty) return const SizedBox.shrink();
    final surface = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0.6,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 20,
                  sigmaY: 20,
                  tileMode: TileMode.decal,
                ),
                child: ServerImage(imageUrl: url, fit: BoxFit.cover),
              ),
            ),
            // Fade the blurred cover into the page surface lower down so it
            // bleeds seamlessly into the chapter list.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    surface.withValues(alpha: 0.0),
                    surface.withValues(alpha: 0.15),
                    surface.withValues(alpha: 0.85),
                    surface,
                  ],
                  stops: const [0.0, 0.4, 0.82, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Accent-glass genre chip — translucent primary-tinted fill + accent border,
/// instead of a stock Material [Chip].
class _GenreChip extends StatelessWidget {
  const _GenreChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(color: cs.onSurface, fontSize: 13),
      ),
    );
  }
}
