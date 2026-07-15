// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/app_sizes.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../../features/offline/data/offline_download_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/theme/brand.dart';
import '../../server_image.dart';
import '../providers/manga_cover_providers.dart';

// Suwayomi's local source uses this sentinel lang code.
const _kLocalSourceLang = 'localsourcelang';

class MangaBadgesRow extends ConsumerWidget {
  const MangaBadgesRow({
    super.key,
    required this.manga,
    this.needSpacer = false,
    this.showCountBadges = false,
    this.padding,
  });
  final MangaDto manga;
  final bool needSpacer;
  final bool showCountBadges;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadedBadge = ref.watch(downloadedBadgeProvider).ifNull(true);
    final unreadBadge = ref.watch(unreadBadgeProvider).ifNull(true);
    final languageBadge = ref.watch(languageBadgeProvider).ifNull(false);
    final useLangIcon = ref.watch(useLangIconProvider).ifNull(false);
    final localBadge = ref.watch(localBadgeProvider).ifNull(false);
    final sourceBadge = ref.watch(sourceBadgeProvider).ifNull(false);

    // At least one chapter downloaded to THIS device — a subset of the server.
    // Empty set when the offline feature is off, so the badge self-hides.
    final onDevice = showCountBadges &&
        (ref.watch(offlineDeviceMangaIdsProvider).valueOrNull ?? const <int>{})
            .contains(manga.id);

    final source = manga.source;
    final isLocal = source?.lang == _kLocalSourceLang;
    final langCode = source?.lang;
    final hasLangBadge = languageBadge && langCode != null && !isLocal;
    final hasLocalBadge = localBadge && isLocal;
    final hasSourceBadge = sourceBadge && source != null && !isLocal;
    final hasEndBadges = showCountBadges &&
        (hasLangBadge || hasLocalBadge || hasSourceBadge || onDevice);

    // When we have end badges, expand the row to full width so the end cluster
    // sits at the top-right corner.
    Widget startBadges = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!showCountBadges && manga.inLibrary.ifNull())
          ClipRRect(
            borderRadius: KBorderRadius.r8.radius,
            child: MangaBadge(
              icon: Icons.collections_bookmark_rounded,
              color: context.theme.colorScheme.primary,
              textColor: context.theme.colorScheme.onPrimary,
            ),
          ),
        if (showCountBadges)
          ClipRRect(
            borderRadius: KBorderRadius.r8.radius,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (manga.unreadCount.isGreaterThan(0) && unreadBadge)
                  MangaBadge(
                    text: "${manga.unreadCount.getValueOnNullOrNegative()}",
                    color: context.theme.colorScheme.primary,
                    textColor: context.theme.colorScheme.onPrimary,
                  ),
                if (manga.downloadCount.isGreaterThan(0) && downloadedBadge)
                  MangaBadge(
                    text: "${manga.downloadCount.getValueOnNullOrNegative()}",
                    color: context.theme.colorScheme.tertiary,
                    textColor: context.theme.colorScheme.onTertiary,
                  ),
              ],
            ),
          ),
      ],
    );

    // Local non-null promotions — guards above ensure these are non-null
    // when the corresponding badge is shown; the aliases enable type promotion.
    final sourceNN = source;
    final langCodeNN = langCode;

    Widget endBadges = ClipRRect(
      borderRadius: KBorderRadius.r8.radius,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDevice) const _OnDeviceBadge(),
          if (hasLangBadge && sourceNN != null && langCodeNN != null)
            useLangIcon
                ? _SourceIconBadge(iconUrl: sourceNN.iconUrl)
                : MangaBadge(
                    text: langCodeNN.toUpperCase(),
                    color: context.theme.colorScheme.secondary,
                    textColor: context.theme.colorScheme.onSecondary,
                  ),
          if (hasLocalBadge)
            MangaBadge(
              icon: Icons.folder_rounded,
              color: context.theme.colorScheme.secondary,
              textColor: context.theme.colorScheme.onSecondary,
            ),
          if (hasSourceBadge && sourceNN != null)
            _SourceIconBadge(iconUrl: sourceNN.iconUrl),
        ],
      ),
    );

    return Padding(
      padding: padding ?? KEdgeInsets.a8.size,
      child: hasEndBadges
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                startBadges,
                endBadges,
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                startBadges,
                if (showCountBadges && needSpacer) const Spacer(),
              ],
            ),
    );
  }
}

/// Passive "on device" badge — this series has at least one chapter downloaded
/// to THIS device. Brand gradient + the app's downloaded pin so it reads as the
/// downloaded motif, distinct from the flat server-download count badge.
class _OnDeviceBadge extends StatelessWidget {
  const _OnDeviceBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: brandGradient(context.theme.colorScheme)),
      child: Padding(
        padding: KEdgeInsets.a4.size,
        child: const Icon(
          Icons.offline_pin_rounded,
          color: onBrandGradient,
          size: 16,
        ),
      ),
    );
  }
}

/// A small badge showing a source icon fetched from the server.
class _SourceIconBadge extends StatelessWidget {
  const _SourceIconBadge({required this.iconUrl});
  final String iconUrl;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.theme.colorScheme.surface,
      child: Padding(
        padding: KEdgeInsets.a4.size,
        child: SizedBox(
          width: 16,
          height: 16,
          child: ServerImage(imageUrl: iconUrl, size: const Size.square(16)),
        ),
      ),
    );
  }
}

class MangaBadge extends StatelessWidget {
  const MangaBadge({
    super.key,
    this.text,
    this.icon,
    required this.color,
    required this.textColor,
  }) : assert(text != null || icon != null);
  final String? text;
  final IconData? icon;
  final Color color;
  final Color textColor;
  @override
  Widget build(BuildContext context) {
    // Flat container (no Material elevation/surfaceTint) so the badge renders
    // the EXACT accent colour at full vividness.
    return ColoredBox(
      color: color,
      child: Padding(
        padding: KEdgeInsets.a4.size,
        child: text.isNotBlank
            ? Text(text!, style: TextStyle(color: textColor))
            : Icon(icon, color: textColor, size: 16),
      ),
    );
  }
}
