// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/search_field.dart';
import '../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../browse_center/presentation/source/controller/source_controller.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../controller/migration_controller.dart';
import '../widgets/migration_source_short_search.dart';

class MigrationGlobalSearchScreen extends HookConsumerWidget {
  const MigrationGlobalSearchScreen({
    super.key,
    required this.sourceManga,
    this.onSelected,
    this.onClose,
  });

  final MangaDto sourceManga;
  final ValueChanged<MangaDto>? onSelected;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState<String?>(sourceManga.title);
    final migrationSearchResult = ref.watch(
      migrationGlobalSearchResultsProvider(
        query: query.value,
        excludeSourceId: sourceManga.sourceId,
      ),
    );

    useEffect(() {
      final initialQuery = sourceManga.title;
      if (initialQuery.isNotEmpty) {
        query.value = initialQuery;
      }
      return null;
    }, []);

    final topBar = onClose == null && showsMergedTopBar(context);
    final title = Text(context.l10n.searchAllSources);
    final searchBox = Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: context.windowSizeClass >= WindowSizeClass.expanded
            ? context.widthScale(scale: .5)
            : null,
        child: Padding(
          padding: KEdgeInsets.h16v4.size,
          child: SearchField(
            initialText: query.value,
            onSubmitted: (value) => query.value = value,
          ),
        ),
      ),
    );
    final results = migrationSearchResult.showUiWhenData(
      context,
      (data) => data.isBlank
          ? Emoticons(
              title: context.l10n.noSourcesFound,
              button: TextButton(
                onPressed: () => ref.invalidate(sourceMapFilteredProvider),
                child: Text(context.l10n.refresh),
              ),
            )
          : ListView.builder(
              itemBuilder: (context, index) {
                return MigrationSourceShortSearch(
                  source: data[index].source,
                  onSelected: onSelected,
                  mangaList: data[index].mangaList,
                  query: query.value,
                );
              },
              itemCount: data.length,
            ),
    );
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
              leading: onClose == null
                  ? detailNavigationBackButton(context)
                  : IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
              title: title,
              bottom: PreferredSize(
                preferredSize: kCalculateAppBarBottomSize([true]),
                child: Column(
                  children: [
                    searchBox,
                  ],
                ),
              ),
            ),
      body: topBar
          ? Column(
              children: [
                searchBox,
                Expanded(child: results),
              ],
            )
          : results,
    );
    return titleTopBarSlot(
      topBar: topBar,
      leading: detailNavigationBackButton(context),
      title: title,
      child: scaffold,
    );
  }
}
