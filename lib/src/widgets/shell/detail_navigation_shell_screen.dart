import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../desktop/desktop_top_bar.dart';
import 'big_screen_navigation_bar.dart';

/// Back button for the AppBars of routes inside [DetailNavigationShellRoute].
///
/// Those routes are pages in the shell's own Navigator, so their
/// `ModalRoute.canPop` is false even when GoRouter has a page underneath;
/// AppBar then drops its implied leading and the screen has no way back. Read
/// the GoRouter stack instead, and fall back to GoRouter's pop when the shell
/// Navigator is at its root.
Widget? detailNavigationBackButton(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    // Not under GoRouter (a screen mounted on its own): the enclosing
    // Navigator is the only stack there is.
    return Navigator.of(context).canPop() ? const BackButton() : null;
  }
  return router.canPop()
      ? BackButton(
          onPressed: () async {
            // The shell Navigator goes first, so a blocking PopScope there
            // (an active selection) still runs. At the shell root it cannot
            // pop, and GoRouter's stack takes over.
            if (await Navigator.of(context).maybePop()) return;
            router.pop();
          },
        )
      : null;
}

class DetailNavigationShellScreen extends ConsumerWidget {
  const DetailNavigationShellScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!context.isTablet) return child;

    final shell = ref.read(navigationShellStateProvider).shell;
    final selectedIndex = shell?.currentIndex ?? 0;
    void goToBranch(int index) {
      if (shell != null) {
        shell.goBranch(index, initialLocation: index == selectedIndex);
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
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (showsMergedTopBar(context)) const DesktopTopBar(),
            // Keyed so a breakpoint toggle moves the body instead of
            // remounting it: the page keeps its scroll, focus and drafts.
            Expanded(
              key: const ValueKey('shellBody'),
              child: Row(
                children: [
                  BigScreenNavigationBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: goToBranch,
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
