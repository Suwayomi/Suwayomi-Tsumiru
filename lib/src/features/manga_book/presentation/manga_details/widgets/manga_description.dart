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
import '../../../../../widgets/gradient_pill_button.dart';
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
            Column(
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
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          icon: Icon(
                            manga.inLibrary.ifNull()
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                          label: Text(
                            manga.inLibrary.ifNull()
                                ? context.l10n.inLibrary
                                : context.l10n.addToLibrary,
                          ),
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
                        ),
                      ),
                      if (manga.realUrl.isNotBlank) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: GlassButton(
                            icon: const Icon(Icons.public_rounded),
                            label: Text(context.l10n.webView),
                            onPressed: () => launchUrlInWeb(
                              context,
                              (manga.realUrl ?? ""),
                              ref.read(toastProvider),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
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
    final cs = Theme.of(context).colorScheme;
    final surface = cs.surface;
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Blurred + saturated cover art (blur 14, ~85%, saturate 1.4 — so
            // the comic's own colors glow rather than wash out to grey).
            Opacity(
              opacity: 0.85,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  1.31496, -0.28608, -0.02888, 0, 0, //
                  -0.08504, 1.11392, -0.02888, 0, 0, //
                  -0.08504, -0.28608, 1.37112, 0, 0, //
                  0, 0, 0, 1, 0, //
                ]),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 14,
                    sigmaY: 14,
                    tileMode: TileMode.decal,
                  ),
                  child: ServerImage(imageUrl: url, fit: BoxFit.cover),
                ),
              ),
            ),
            // Indigo→cyan brand tint over the top (55% strength).
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.primary.withValues(alpha: 0.22),
                    cs.secondary.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 0.72],
                ),
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
                    surface.withValues(alpha: 0.10),
                    surface.withValues(alpha: 0.85),
                    surface,
                  ],
                  stops: const [0.0, 0.45, 0.85, 1.0],
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
/// On-brand palette for per-genre coloring — vivid but dark-theme-friendly.
const _genrePalette = <Color>[
  Color(0xFF7C7BFF), // indigo
  Color(0xFF33D6FF), // cyan
  Color(0xFF34E0A1), // mint
  Color(0xFFFFCF5C), // amber
  Color(0xFFFF5DB1), // pink
  Color(0xFFB06BFF), // purple
  Color(0xFF2DD4BF), // teal
  Color(0xFFFF9F5C), // orange
  Color(0xFF5B9BFF), // blue
  Color(0xFFFF6B6B), // coral
];

/// Stable per-genre color: the same genre always maps to the same hue.
Color _genreColor(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _genrePalette[h % _genrePalette.length];
}

class _GenreChip extends StatelessWidget {
  const _GenreChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    // Each genre gets its own stable color.
    final accent = _genreColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.16), blurRadius: 12),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
