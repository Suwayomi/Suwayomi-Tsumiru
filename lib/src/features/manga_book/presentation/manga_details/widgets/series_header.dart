import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../routes/navigation.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../../../widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import '../../../../browse_center/domain/source/source_model.dart';
import '../../../domain/manga/manga_model.dart';
import '../controller/manga_details_controller.dart';
import 'manga_rating_bar.dart';

class SeriesAppBarTitle extends StatelessWidget {
  const SeriesAppBarTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: title,
    child: LayoutBuilder(
      builder: (context, constraints) {
        var size = 20.0;
        final base = context.textTheme.titleMedium!.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.25,
        );
        while (size > 15) {
          final painter = TextPainter(
            text: TextSpan(
              text: title,
              style: base.copyWith(fontSize: size),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final fits = painter.width <= constraints.maxWidth;
          painter.dispose();
          if (fits) break;
          size--;
        }
        return Text(
          title,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: base.copyWith(fontSize: size),
        );
      },
    ),
  );
}

class SeriesHeader extends ConsumerWidget {
  const SeriesHeader({
    super.key,
    required this.manga,
    required this.onLibraryPressed,
    this.belowStatus,
  });

  final MangaDto manga;
  final VoidCallback onLibraryPressed;
  final Widget? belowStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = context.isDesktop;
    final coverWidth = desktop ? 180.0 : 140.0;
    final next = desktop
        ? ref.watch(firstUnreadInFilteredChapterListProvider(mangaId: manga.id))
        : null;
    final inLibrary = manga.inLibrary.ifNull();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                key: const ValueKey('series-header-cover'),
                width: coverWidth,
                height: coverWidth * 1.5,
                child: CardTheme(
                  data: CardTheme.of(context).copyWith(margin: EdgeInsets.zero),
                  child: MangaCoverGridTile(
                    manga: manga,
                    showBadges: false,
                    showTitle: false,
                    showDarkOverlay: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  if (!desktop) ...[
                    InkWell(
                      onTap: () =>
                          openGlobalSearch(context, query: manga.title),
                      child: Text(
                        manga.title,
                        style: context.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  InkWell(
                    onTap: manga.author.isNotBlank
                        ? () => openGlobalSearch(context, query: manga.author)
                        : null,
                    child: Text(
                      manga.author ?? context.l10n.unknownAuthor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        MangaStatus.fromJson(manga.status.name).icon,
                        size: 16,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              MangaStatus.fromJson(
                                manga.status.name,
                              ).toLocale(context),
                              style: context.textTheme.bodySmall,
                            ),
                            if (manga.source?.displayName != null) ...[
                              const Text(' • '),
                              InkWell(
                                onTap: manga.source!.id.isNotBlank
                                    ? () => SourceTypeRoute(
                                        sourceId: manga.source!.id,
                                        sourceType: SourceType.POPULAR,
                                      ).go(context)
                                    : null,
                                child: Text(
                                  manga.source!.displayName,
                                  style: context.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (belowStatus != null) ...[
                    const SizedBox(height: 6),
                    belowStatus!,
                  ],
                  if (desktop) ...[
                    const Spacer(),
                    const SizedBox(height: 10),
                    MangaRatingBar(mangaId: manga.id, compact: true),
                    const SizedBox(height: 4),
                    Row(
                      key: const ValueKey('series-header-controls'),
                      children: [
                        if (next != null) ...[
                          Flexible(
                            child: SeriesHeaderPill(
                              gradient: true,
                              icon: Icons.play_arrow_rounded,
                              label:
                                  manga.lastReadChapter?.hasReadingProgress ==
                                      true
                                  ? context.l10n.resume
                                  : context.l10n.start,
                              onPressed: () => ReaderRoute(
                                mangaId: next.mangaId,
                                chapterId: next.id,
                                showReaderLayoutAnimation: true,
                              ).push(context),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: SeriesHeaderPill(
                            icon: inLibrary
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            label: inLibrary
                                ? context.l10n.inLibrary
                                : context.l10n.addToLibrary,
                            onPressed: onLibraryPressed,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SeriesHeaderPill extends HookWidget {
  const SeriesHeaderPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.gradient = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final hovered = useState(false);
    final pressed = useState(false);
    final focused = useState(false);
    final highlighted = hovered.value || focused.value;
    final cs = context.colorScheme;
    final brand = BrandColors.of(context);
    final radius = BorderRadius.circular(18);
    final fill = gradient
        ? OnImage.text.withValues(
            alpha: pressed.value
                ? .24
                : highlighted
                ? .16
                : 0,
          )
        : cs.primary.withValues(
            alpha: pressed.value
                ? .26
                : highlighted
                ? .18
                : .10,
          );
    return MouseRegion(
      onEnter: (_) => hovered.value = true,
      onExit: (_) {
        hovered.value = false;
        pressed.value = false;
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: context.reduceMotion ? 0 : 120),
        decoration: BoxDecoration(
          gradient: gradient ? brand.gradient : null,
          borderRadius: radius,
          border: gradient
              ? null
              : Border.all(color: cs.primary.withValues(alpha: .45)),
          boxShadow: gradient
              ? [
                  BoxShadow(
                    color: cs.secondary.withValues(
                      alpha: highlighted ? .45 : .25,
                    ),
                    blurRadius: highlighted ? 22 : 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            onFocusChange: (value) => focused.value = value,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            onHighlightChanged: (value) => pressed.value = value,
            borderRadius: radius,
            child: Ink(
              color: fill,
              padding: EdgeInsets.symmetric(
                horizontal: gradient ? 22 : 20,
                vertical: gradient ? 12 : 11,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: gradient ? brand.onGradient : cs.primary,
                  ),
                  SizedBox(width: gradient ? 6 : 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: gradient ? brand.onGradient : cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
