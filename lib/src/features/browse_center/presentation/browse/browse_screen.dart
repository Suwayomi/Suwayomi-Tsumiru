// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/motion/reduce_motion.dart';
import '../../../../widgets/desktop/desktop_top_bar.dart';
import '../../../migration/controller/bulk_migration_providers.dart';
import '../../../quick_open/presentation/unified_search/desktop_search_field.dart';
import '../../../quick_open/presentation/unified_search/phone_search_view.dart';
import '../../../settings/presentation/library/widgets/persistent_search_bar/persistent_search_bar.dart';
import '../extension/controller/extension_controller.dart';
import '../extension/widgets/extension_language_filter_dialog.dart';
import '../extension/widgets/install_extension_file.dart';
import '../source/controller/source_controller.dart' hide SourceLanguageFilter;
import '../source/widgets/source_language_filter.dart';

class BrowseScreen extends HookConsumerWidget {
  const BrowseScreen({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.children,
  });
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabController = useTabController(
      initialLength: 3,
      initialIndex: currentIndex,
      animationDuration: context.reduceMotion
          ? Duration.zero
          : kTabScrollDuration,
      keys: [context.reduceMotion],
    );

    useEffect(() {
      if (currentIndex != tabController.index) {
        tabController.animateTo(currentIndex);
      }
      return null;
    }, [currentIndex]);

    useEffect(() {
      if (currentIndex != tabController.index) {
        Future.microtask(() => onDestinationSelected(tabController.index));
      }
      return null;
    }, [tabController.index]);
    useListenable(tabController);
    final phone = context.windowSizeClass == WindowSizeClass.compact;
    final persistentBox =
        phone && ref.watch(libraryPersistentSearchBarProvider).ifNull();

    final topBar = showsMergedTopBar(context);
    final search = _BrowseDesktopSearch(tabIndex: tabController.index);
    final actions = <Widget>[
      if (tabController.index == 0) ...[
        if (phone && !persistentBox) ...[
          const PhoneSearchClearFilter(origin: PhoneSearchOrigin.sources),
          const PhoneSearchEntry(origin: PhoneSearchOrigin.sources),
        ],
        IconButton(
          tooltip: context.l10n.filterSources,
          onPressed: () => const SourceFilterRoute().push(context),
          icon: const Icon(FluentIcons.filter_24_regular),
        ),
      ],
      if (tabController.index == 1) ...[
        IconButton(
          tooltip: context.l10n.extensionStores,
          onPressed: () => const ExtensionStoreRoute().push(context),
          icon: const Icon(FluentIcons.puzzle_piece_24_regular),
        ),
        const InstallExtensionFile(),
      ],
      if (tabController.index != 2)
        IconButton(
          onPressed: () => showDialog(
            context: context,
            builder: (context) => tabController.index == 0
                ? const SourceLanguageFilter()
                : const ExtensionLanguageFilterDialog(),
            animationStyle: context.motionStyle,
          ),
          icon: const Icon(FluentIcons.translate_24_regular),
        ),
    ];
    final tabBar = TabBar(
      dividerColor: Colors.transparent,
      isScrollable: context.windowSizeClass >= WindowSizeClass.medium,
      controller: tabController,
      tabs: [
        Tab(text: context.l10n.sources),
        Tab(text: context.l10n.extensions),
        Tab(text: context.l10n.migrate),
      ],
    );
    final scaffold = Scaffold(
      appBar: topBar
          ? null
          : AppBar(
        title: context.usesDesktopShell
            ? Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: search,
                ),
              )
            : Text(context.l10n.browse),
        actions: actions,
        bottom: tabBar,
      ),
      body: topBar
          ? Column(
              children: [
                tabBar,
                Expanded(
                  child: TabBarView(
                    controller: tabController,
                    children: children,
                  ),
                ),
              ],
            )
          : TabBarView(controller: tabController, children: children),
    );
    return topBar
        ? TopBarSlot(
            content: desktopSearchSlotContent(search: search, actions: actions),
            minWidth: searchTopBarSlotMinWidth(actions.length),
            child: scaffold,
          )
        : scaffold;
  }
}

class _BrowseDesktopSearch extends ConsumerWidget {
  const _BrowseDesktopSearch({required this.tabIndex});

  final int tabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final String query;
    final ValueChanged<String> onChanged;
    final String hint;
    switch (tabIndex) {
      case 1:
        query = ref.watch(extensionQueryProvider) ?? '';
        onChanged = (value) =>
            ref.read(extensionQueryProvider.notifier).update(value);
        hint = l10n.searchExtensionsHint;
      case 2:
        query = ref.watch(migrationSourcePickerQueryProvider);
        onChanged = (value) =>
            ref.read(migrationSourcePickerQueryProvider.notifier).update(value);
        hint = l10n.searchSourcesHint;
      default:
        query = ref.watch(sourceSearchQueryProvider) ?? '';
        onChanged = (value) =>
            ref.read(sourceSearchQueryProvider.notifier).update(value);
        hint = l10n.searchSourcesHint;
    }
    return DesktopSearchField(
      query: query,
      onChanged: onChanged,
      onNavigate: () => onChanged(''),
      hintText: hint,
    );
  }
}
