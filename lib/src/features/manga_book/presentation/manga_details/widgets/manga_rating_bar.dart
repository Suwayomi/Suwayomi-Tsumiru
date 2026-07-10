// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../controller/manga_details_controller.dart';

/// A tappable 0-5 star row for the reader's personal rating of a manga. Tapping
/// the current top star clears the rating.
class MangaRatingBar extends ConsumerWidget {
  const MangaRatingBar({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rating = ref.watch(mangaRatingProvider(mangaId: mangaId));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            context.l10n.yourRating,
            style: context.textTheme.titleSmall,
          ),
          const Spacer(),
          for (int star = 1; star <= 5; star++)
            InkResponse(
              radius: 20,
              onTap: () => ref
                  .read(mangaRatingProvider(mangaId: mangaId).notifier)
                  .update(rating == star ? 0 : star),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  star <= rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  // Conventional amber reads on every theme; the theme accent
                  // isn't always a sensible star colour.
                  color: star <= rating ? Colors.amber : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
