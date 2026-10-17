import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import 'big_screen_navigation_bar.dart';

class DetailNavigationShellScreen extends ConsumerWidget {
  const DetailNavigationShellScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!context.isTablet) return child;

    final shell = ref.read(navigationShellStateProvider).shell;
    final selectedIndex = shell?.currentIndex ?? 0;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            BigScreenNavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                if (shell != null) {
                  shell.goBranch(
                    index,
                    initialLocation: index == selectedIndex,
                  );
                  return;
                }
                switch (index) {
                  case 0:
                    const LibraryRoute(categoryId: 0).go(context);
                  case 1:
                    const UpdatesRoute().go(context);
                  case 2:
                    const HistoryTabRoute().go(context);
                  case 3:
                    const BrowseSourceRoute().go(context);
                  case 4:
                    const DownloadsRoute().go(context);
                  case 5:
                    const MoreRoute().go(context);
                }
              },
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
