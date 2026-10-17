// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../routes/navigation.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../migration/domain/migration_models.dart';
import '../../../../offline/data/offline_repository.dart';
import '../../../../offline/presentation/series_offline_button.dart';
import '../../../../tracking/presentation/hub/track_sheet.dart';
import '../../../domain/manga/manga_model.dart';
import '../controller/manga_details_controller.dart';
import '../controller/next_update_controller.dart';
import '../server_web_url.dart';
import 'chapter_download_presets_button.dart';
import 'edit_manga_category_dialog.dart';
import 'manga_action_button.dart';
import 'manga_rating_bar.dart';
import 'manga_user_tags_row.dart';
import 'series_header.dart';
import 'tag_actions_menu.dart';

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

  /// "Web View" → choose the source site (realUrl) or the Suwayomi server's
  /// WebUI page for this manga. With no source page, opens the server directly.
  static void openInBrowser(
    BuildContext context,
    WidgetRef ref,
    MangaDto manga,
  ) {
    final toast = ref.read(toastProvider);
    final serverUrl = serverMangaWebUrl(ref, manga.id);
    if (manga.realUrl.isBlank) {
      if (serverUrl != null) launchUrlInWeb(context, serverUrl, toast);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: Text(sheetContext.l10n.openSourceInBrowser),
              onTap: () {
                Navigator.pop(sheetContext);
                launchUrlInWeb(context, manga.realUrl ?? '', toast);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns_rounded),
              title: Text(sheetContext.l10n.openOnServer),
              onTap: () {
                Navigator.pop(sheetContext);
                if (serverUrl != null) {
                  launchUrlInWeb(context, serverUrl, toast);
                }
              },
            ),
          ],
        ),
      ),
      sheetAnimationStyle: context.motionStyle,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpanded = useState(false);
    final cs = context.theme.colorScheme;
    final surface = context.theme.scaffoldBackgroundColor;
    final inLibrary = manga.inLibrary.ifNull();
    final moreKey = useMemoized(
      () => GlobalKey<PopupMenuButtonState<String>>(),
    );
    Future<void> toggleLibrary() async {
      final val = await AsyncValue.guard(() async {
        if (inLibrary) {
          await removeMangaFromLibrary();
        } else {
          await addMangaToLibrary();
        }
        await refresh();
      });
      if (context.mounted) val.showToastOnError(ref.read(toastProvider));
    }

    final prediction = ref.watch(mangaNextUpdateProvider(mangaId: manga.id));
    final soonDays = manga.status == Enum$MangaStatus.COMPLETED
        ? null
        : prediction?.daysUntil(DateTime.now());

    final soonWidget = soonDays == null
        ? null
        : InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(context.l10n.smartUpdate),
                content: Text(
                  context.l10n.smartUpdateExpected(
                    context.l10n.dayCount(soonDays),
                    context.l10n.dayCount(prediction?.intervalDays ?? 7),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(context.l10n.close),
                  ),
                ],
              ),
              animationStyle: context.motionStyle,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hourglass_empty_rounded,
                  size: 14,
                  color: soonDays <= 1
                      ? cs.primary
                      : context.textTheme.bodySmall?.color,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    context.isTablet
                        ? context.l10n.seriesNextChapterExpected(soonDays)
                        : soonDays == 0
                        ? context.l10n.soon
                        : context.l10n.inNDays(soonDays),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: soonDays <= 1 ? cs.primary : null,
                    ),
                  ),
                ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (context.isTablet)
          SeriesHeader(
            manga: manga,
            belowStatus: soonWidget,
            onLibraryPressed: toggleLibrary,
          )
        else
          Stack(
            children: [
              if (manga.thumbnailUrl.isNotBlank)
                Positioned.fill(
                  child: ClipRect(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: ColorFiltered(
                        colorFilter: BrandColors.of(context).neutral
                            ? const ColorFilter.matrix(<double>[
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0,
                                0,
                                0,
                                1,
                                0,
                              ])
                            : const ColorFilter.mode(
                                Colors.transparent,
                                BlendMode.dst,
                              ),
                        child: ServerImage(
                          imageUrl: manga.thumbnailUrl ?? "",
                          fit: BoxFit.cover,
                        ),
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
                // Clear only the status bar; the transparent app-bar icons float
                // over the top of the hero so the cover rides up into the backdrop
                // instead of leaving a dead toolbar-height band above it.
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + 8,
                ),
                child: MangaCoverDescriptiveListTile(
                  manga: manga,
                  showBadges: false,
                  onTitleClicked: (query) =>
                      openGlobalSearch(context, query: query),
                  belowStatus: soonWidget,
                  titleMaxLines: null,
                ),
              ),
            ],
          ),
        Builder(
          builder: (context) {
            final offlineEnabled = ref.watch(offlineEnabledProvider);
            return Padding(
              padding: context.isDesktop
                  ? const EdgeInsets.fromLTRB(16, 4, 16, 4)
                  : const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (context.isDesktop) ...[
                    Divider(height: 1, color: cs.outlineVariant),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      if (!context.isDesktop)
                        Expanded(
                          child: MangaActionButton(
                            active: inLibrary,
                            icon: Icon(
                              inLibrary
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                            ),
                            label: inLibrary
                                ? context.l10n.inLibrary
                                : context.l10n.addToLibrary,
                            onPressed: toggleLibrary,
                          ),
                        ),
                      Expanded(
                        child: MangaActionButton(
                          active: manga.trackRecords.nodes.isNotEmpty,
                          icon: const Icon(Icons.sync_rounded),
                          label: context.l10n.tracking,
                          onPressed: () => showTrackSheet(
                            context,
                            manga.id,
                            mangaTitle: manga.title,
                          ),
                        ),
                      ),
                      if (offlineEnabled)
                        Expanded(child: SeriesOfflineButton(mangaId: manga.id)),
                      if (!manga.isLocalSource)
                        Expanded(
                          child: ChapterDownloadPresetsButton(
                            actionRow: true,
                            chapterList: ref.watch(
                              mangaChapterListForBulkActionsProvider(
                                mangaId: manga.id,
                              ),
                            ),
                            refresh: (_) => refresh(),
                          ),
                        ),
                      if (context.isTablet)
                        Expanded(
                          child: PopupMenuButton<String>(
                            key: moreKey,
                            tooltip: context.l10n.more,
                            popUpAnimationStyle: context.motionStyle,
                            onSelected: (value) {
                              switch (value) {
                                case 'categories':
                                  showDialog<void>(
                                    context: context,
                                    builder: (_) => EditMangaCategoryDialog(
                                      mangaId: manga.id,
                                    ),
                                    animationStyle: context.motionStyle,
                                  );
                                case 'migrate':
                                  MigrationBulkConfigRoute(
                                    $extra: MigrationBulkConfigData(
                                      mangaIds: [manga.id],
                                    ),
                                  ).push(context);
                                case 'web':
                                  openInBrowser(context, ref, manga);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'categories',
                                child: Text(context.l10n.categories),
                              ),
                              PopupMenuItem(
                                value: 'migrate',
                                child: Text(context.l10n.migrate),
                              ),
                              PopupMenuItem(
                                value: 'web',
                                child: Text(context.l10n.webView),
                              ),
                            ],
                            child: MangaActionButton(
                              icon: const Icon(Icons.more_horiz_rounded),
                              label: context.l10n.more,
                              onPressed: () =>
                                  moreKey.currentState?.showButtonMenu(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        if (!context.isDesktop) MangaRatingBar(mangaId: manga.id),
        if (manga.description.isNotBlank)
          Padding(
            padding: KEdgeInsets.a16.size,
            child: MangaDescriptionBody(
              description: manga.description!,
              isExpanded: isExpanded.value,
              onToggleExpanded: () => isExpanded.value = !isExpanded.value,
              onOpenLink: (url) =>
                  launchUrlInWeb(context, url, ref.read(toastProvider)),
            ),
          ),
        if (isExpanded.value)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AddUserTagChip(mangaId: manga.id),
                ...manga.genre
                    .where((e) => e.isNotBlank)
                    .map<Widget>(
                      (e) => Builder(
                        builder: (chipContext) => _SeriesGenreChip(
                          label: e,
                          onTap: () =>
                              showTagActionsMenu(chipContext, ref, tag: e),
                        ),
                      ),
                    ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: CollapsedSeriesTags(
              tags: manga.genre.where((e) => e.isNotBlank).toList(),
              leading: AddUserTagChip(mangaId: manga.id),
              onExpand: () => isExpanded.value = true,
              onTagTap: (chipContext, tag) =>
                  showTagActionsMenu(chipContext, ref, tag: tag),
            ),
          ),
        MangaUserTagsRow(mangaId: manga.id),
      ],
    );
  }
}

class MangaDescriptionBody extends StatelessWidget {
  const MangaDescriptionBody({
    super.key,
    required this.description,
    required this.isExpanded,
    required this.onToggleExpanded,
    this.onOpenLink,
  });

  final String description;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style;
    final fontSize = textStyle.fontSize ?? 14;
    final lineHeight = fontSize * (textStyle.height ?? 1.4);
    final markdownBody = MarkdownBody(
      data: description,
      onTapLink: (_, href, _) {
        if (href.isNotBlank) onOpenLink?.call(href!);
      },
      styleSheet: MarkdownStyleSheet.fromTheme(context.theme).copyWith(
        p: textStyle,
        a: textStyle.copyWith(color: context.theme.colorScheme.primary),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isExpanded)
          markdownBody
        else
          Stack(
            children: [
              ClipRect(
                child: SizedBox(
                  height: lineHeight * 5,
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: markdownBody,
                  ),
                ),
              ),
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                height: lineHeight,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          context.theme.scaffoldBackgroundColor.withValues(
                            alpha: 0,
                          ),
                          context.theme.scaffoldBackgroundColor.withValues(
                            alpha: .9,
                          ),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        InkWell(
          onTap: onToggleExpanded,
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Icon(
              isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
          ),
        ),
      ],
    );
  }
}

class CollapsedSeriesTags extends StatelessWidget {
  const CollapsedSeriesTags({
    super.key,
    required this.tags,
    required this.leading,
    required this.onExpand,
    required this.onTagTap,
  });

  final List<String> tags;
  final Widget leading;
  final VoidCallback onExpand;
  final void Function(BuildContext, String) onTagTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(
        context,
      ).style.copyWith(fontSize: 12, fontWeight: FontWeight.w600);
      double textWidth(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      var count = tags.length;
      while (count > 0) {
        final moreWidth = count < tags.length
            ? 8 +
                  textWidth(context.l10n.seriesTagsMore(tags.length - count)) +
                  30
            : 0;
        final width =
            38 +
            tags
                .take(count)
                .fold<double>(0, (sum, tag) => sum + 8 + textWidth(tag) + 30) +
            moreWidth;
        if (width <= constraints.maxWidth) break;
        count--;
      }
      return Row(
        children: [
          leading,
          for (final tag in tags.take(count)) ...[
            const SizedBox(width: 8),
            Builder(
              builder: (chipContext) => _SeriesGenreChip(
                label: tag,
                onTap: () => onTagTap(chipContext, tag),
              ),
            ),
          ],
          if (count < tags.length) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Material(
                color: context.colorScheme.onSurface.withValues(alpha: .06),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: context.colorScheme.onSurface.withValues(alpha: .18),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onExpand,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    child: Text(
                      context.l10n.seriesTagsMore(tags.length - count),
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _SeriesGenreChip extends StatelessWidget {
  const _SeriesGenreChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      BrandChip(label: label),
      Positioned.fill(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
          ),
        ),
      ),
    ],
  );
}
