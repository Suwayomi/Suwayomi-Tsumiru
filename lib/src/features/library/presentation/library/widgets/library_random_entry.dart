import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/enum.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../category/controller/edit_category_controller.dart';
import '../controller/library_controller.dart';
import '../controller/library_grouping.dart';

VoidCallback randomLibraryEntryAction(BuildContext context, WidgetRef ref) {
  final tabs = DefaultTabController.maybeOf(context);
  return () {
    final groupType = ref.read(libraryGroupTypeProvider) ?? 0;
    final style =
        ref.read(libraryGroupStyleKeyProvider) ?? LibraryGroupStyle.tabs;
    final allSections =
        style == LibraryGroupStyle.headers &&
        (ref.read(sectionHeadersShowAllCategoriesProvider) ?? false);
    final visibleSection = allSections
        ? ref.read(libraryVisibleSectionProvider)
        : null;
    final candidates = <MangaDto>[];
    if (groupType == 0) {
      final categories =
          ref.read(visibleCategoryListProvider).value ?? const [];
      for (var i = 0; i < categories.length; i++) {
        if (visibleSection != null
            ? categories[i].id != visibleSection
            : i != (tabs?.index ?? 0)) {
          continue;
        }
        candidates.addAll(
          ref
                  .read(
                    categoryMangaListWithQueryAndFilterProvider(
                      categoryId: categories[i].id,
                    ),
                  )
                  .value ??
              const [],
        );
      }
    } else {
      final groups = ref.read(libraryGroupedTabsProvider).value ?? const [];
      for (var i = 0; i < groups.length; i++) {
        if (visibleSection != null
            ? groups[i].id != visibleSection
            : i != (tabs?.index ?? 0)) {
          continue;
        }
        candidates.addAll(
          ref
                  .read(
                    groupedMangaListWithQueryAndFilterProvider(
                      tabId: groups[i].id,
                    ),
                  )
                  .value ??
              const [],
        );
      }
    }
    final unique = {
      for (final manga in candidates) manga.id: manga,
    }.values.toList();
    if (unique.isEmpty) return;
    MangaRoute(
      mangaId: unique[Random().nextInt(unique.length)].id,
    ).push(context);
  };
}

class LibraryRandomEntryButton extends ConsumerWidget {
  const LibraryRandomEntryButton({super.key, required this.libraryContext});
  final BuildContext libraryContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: context.l10n.openRandomEntry,
    icon: const Icon(FluentIcons.arrow_shuffle_24_regular),
    onPressed: randomLibraryEntryAction(libraryContext, ref),
  );
}
