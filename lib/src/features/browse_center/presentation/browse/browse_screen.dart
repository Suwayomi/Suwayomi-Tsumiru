// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../data/extension_store_repository/extension_store_repository.dart';
import '../extension/widgets/extension_language_filter_dialog.dart';
import '../extension/widgets/install_extension_file.dart';
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
    final tabController =
        useTabController(initialLength: 3, initialIndex: currentIndex);

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

    final storeCapable =
        ref.watch(extensionStoreSupportProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.browse),
        actions: [
          if (tabController.index == 0) ...[
            IconButton(
              tooltip: context.l10n.globalSearch,
              onPressed: () => const GlobalSearchRoute().push(context),
              icon: const Icon(Icons.travel_explore_rounded),
            ),
            IconButton(
              tooltip: context.l10n.filterSources,
              onPressed: () => const SourceFilterRoute().push(context),
              icon: const Icon(Icons.filter_list_rounded),
            ),
          ],
          if (tabController.index == 1) ...[
            IconButton(
              tooltip: storeCapable
                  ? context.l10n.extensionStores
                  : context.l10n.extensionRepository,
              onPressed: () => storeCapable
                  ? const ExtensionStoreRoute().push(context)
                  : const ExtensionRepositoryRoute().push(context),
              icon: const Icon(Icons.dns_rounded),
            ),
            const InstallExtensionFile(),
          ],
          // Language filter applies to Sources/Extensions only, not Migrate.
          if (tabController.index != 2)
            IconButton(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => tabController.index == 0
                    ? const SourceLanguageFilter()
                    : const ExtensionLanguageFilterDialog(),
              ),
              icon: const Icon(Icons.translate_rounded),
            ),
        ],
        bottom: TabBar(
          dividerColor: Colors.transparent,
          isScrollable: context.isTablet,
          controller: tabController,
          tabs: [
            Tab(text: context.l10n.sources),
            Tab(text: context.l10n.extensions),
            Tab(text: context.l10n.migrate),
          ],
        ),
      ),
      body: TabBarView(controller: tabController, children: children),
    );
  }
}
