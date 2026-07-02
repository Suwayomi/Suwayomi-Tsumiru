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
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/launch_url_in_web.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../utils/theme/brand.dart';
import '../../../../../widgets/manga_cover/list/manga_cover_descriptive_list_tile.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../offline/data/offline_repository.dart';
import '../../../../offline/presentation/series_offline_button.dart';
import '../../../../tracking/presentation/hub/track_sheet.dart';
import '../../../domain/manga/manga_model.dart';
import '../controller/next_update_controller.dart';
import '../server_web_url.dart';
import 'manga_action_button.dart';

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
  void _openInBrowser(BuildContext context, WidgetRef ref) {
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
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpanded = useState(context.isTablet);
    final cs = context.theme.colorScheme;
    final surface = context.theme.scaffoldBackgroundColor;
    final inLibrary = manga.inLibrary.ifNull();

    final prediction = ref.watch(mangaNextUpdateProvider(mangaId: manga.id));
    final soonDays = manga.status == Enum$MangaStatus.COMPLETED
        ? null
        : prediction?.daysUntil(DateTime.now());

    // Build the Soon line for the header metadata column.
    final soonWidget = soonDays == null
        ? null
        : GestureDetector(
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
                Text(
                  soonDays == 0
                      ? context.l10n.soon
                      : context.l10n.inNDays(soonDays),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: soonDays <= 1 ? cs.primary : null,
                  ),
                ),
              ],
            ),
          );

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
                belowStatus: soonWidget,
              ),
            ),
          ],
        ),
        Builder(builder: (context) {
          // Action row: equal-width icon-over-label columns.
          final offlineEnabled = ref.watch(offlineEnabledProvider);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Row(
              children: [
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
                Expanded(
                  child: MangaActionButton(
                    active: manga.trackRecords.totalCount > 0,
                    icon: const Icon(Icons.sync_rounded),
                    label: context.l10n.tracking,
                    onPressed: () => showTrackSheet(context, manga.id,
                        mangaTitle: manga.title),
                  ),
                ),
                if (offlineEnabled)
                  Expanded(child: SeriesOfflineButton(mangaId: manga.id)),
                Expanded(
                  child: MangaActionButton(
                    icon: const Icon(Icons.public_rounded),
                    label: context.l10n.webView,
                    onPressed: () => _openInBrowser(context, ref),
                  ),
                ),
              ],
            ),
          );
        }),
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
