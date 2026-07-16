// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../constants/language_list.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/emoticons.dart';
import '../../../../widgets/search_field.dart';
import 'controller/source_controller.dart';
import 'widgets/source_list_tile.dart';

class SourceScreen extends HookConsumerWidget {
  const SourceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceMapData = ref.watch(sourceMapFilteredAndQueriedProvider);
    final query = ref.watch(sourceSearchQueryProvider);
    final allPinned = ref.watch(pinnedSourcesProvider);
    final pinned = query.isBlank
        ? allPinned
        : allPinned.where((s) => s.name.query(query)).toList();

    final sourceMap = {...?sourceMapData.value};
    final localSource = sourceMap.remove("localsourcelang");
    final lastUsed = sourceMap.remove("lastUsed");
    final allSource = sourceMap.remove("all");

    refresh() => ref.refresh(sourceListProvider.future);
    useEffect(() {
      if (sourceMapData.isNotLoading) refresh();
      return;
    }, []);

    useEffect(() {
      sourceMapData.showToastOnError(
        ref.read(toastProvider),
        withMicrotask: true,
      );
      return;
    }, [sourceMapData.value]);

    final body = sourceMapData.showUiWhenData(
      context,
      (data) {
        if ((sourceMap.isEmpty &&
            localSource.isBlank &&
            lastUsed.isBlank &&
            pinned.isEmpty)) {
          return Emoticons(
            title: context.l10n.noSourcesFound,
            button: TextButton(
              onPressed: refresh,
              child: Text(context.l10n.refresh),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: CustomScrollView(
            slivers: [
              if (pinned.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: ListTile(
                    title: Text(languageMap["pinned"]?.displayName ?? ""),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => SourceListTile(source: pinned[index]),
                    childCount: pinned.length,
                  ),
                ),
              ],
              if (lastUsed.isNotBlank) ...[
                SliverToBoxAdapter(
                  child: ListTile(
                    title: Text(languageMap["lastUsed"]?.displayName ?? ""),
                  ),
                ),
                SliverToBoxAdapter(
                    child: SourceListTile(source: lastUsed!.first))
              ],
              if (allSource.isNotBlank) ...[
                SliverToBoxAdapter(
                  child: ListTile(
                    title: Text(languageMap["all"]?.displayName ?? ""),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => SourceListTile(
                      source: allSource![index],
                    ),
                    childCount: allSource?.length,
                  ),
                )
              ],
              for (final k in sourceMap.keys) ...[
                if (sourceMap[k].isNotBlank) ...[
                  SliverToBoxAdapter(
                    child:
                        ListTile(title: Text(languageMap[k]?.displayName ?? k)),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => SourceListTile(
                        source: sourceMap[k]![index],
                      ),
                      childCount: sourceMap[k]?.length,
                    ),
                  )
                ]
              ],
              if (localSource.isNotBlank) ...[
                SliverToBoxAdapter(
                  child: ListTile(
                    title:
                        Text(languageMap["localsourcelang"]?.displayName ?? ""),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SourceListTile(source: localSource!.first),
                )
              ],
            ],
          ),
        );
      },
      refresh: refresh,
    );

    return Column(
      children: [
        SearchField(
          autofocus: false,
          hintText: context.l10n.searchForSources,
          initialText: query,
          onChanged: (val) =>
              ref.read(sourceSearchQueryProvider.notifier).update(val),
        ),
        Expanded(child: body),
      ],
    );
  }
}
