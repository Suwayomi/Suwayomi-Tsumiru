part of 'router_config.dart';

/// Page for routes that draw their own copy of the sidebar inside
/// [DetailNavigationShellScreen] (settings/account pages, source pages,
/// Upcoming), and for [DetailNavigationShellRoute] itself, which hosts the
/// series page and the other detail routes in its own Navigator.
///
/// On tablet and wider the sidebar is identical on both sides of the push, so
/// the default zoom would animate the sidebar along with the page and the app
/// looks like it jumps. A short fade keeps the sidebar visually still while
/// the content changes. Phones keep the default platform transition, and
/// reduced motion skips the fade entirely.
///
/// The width check only picks the transition style, never the page type: the
/// page is always a [CustomTransitionPage] with [GoRouterState.pageKey], so
/// resizing across the 600 px breakpoint updates the route in place instead
/// of replacing it.
Page<void> detailNavigationPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  return _detailNavigationPage(
    context,
    state,
    DetailNavigationShellScreen(child: child),
  );
}

/// The outer shells' own page ([QuickSearchRoute] and [NavigationShellRoute]):
/// whenever either enters with the sidebar inside (a sidebar jump with no
/// main shell underneath, e.g. after a deep link or restart, or the root
/// page leaving from above it), the default slide would animate the sidebar
/// along with the page. It needs the same fade as the detail pages, so the
/// sidebar stays still in every direction. Branch switches never rebuild
/// these pages; pushes above them keep their own transitions.
Page<void> navigationShellPage(
  BuildContext context,
  GoRouterState state,
  Widget shell,
) {
  return _detailNavigationPage(context, state, shell);
}

/// The shell's own page: entering or leaving the detail shell from the main
/// navigation transitions this page (sidebar included), so it needs the same
/// fade as the routes above. Pushes inside the shell animate only the inner
/// Navigator's pages, where the sidebar sits outside and stays still.
Page<void> detailNavigationShellPage(
  BuildContext context,
  GoRouterState state,
  Widget navigator,
) {
  return _detailNavigationPage(
    context,
    state,
    DetailNavigationShellScreen(child: navigator),
  );
}

Page<void> _detailNavigationPage(
  BuildContext context,
  GoRouterState state,
  Widget pageChild,
) {
  // The page identity (runtimeType + key) must not depend on the window
  // width. pageBuilder re-runs on every resize, and swapping MaterialPage
  // for CustomTransitionPage replaces the route, stacking an exiting copy
  // of every shell above the new one. Flipping back before the 150 ms exit
  // finishes wedges the Navigator update and hangs the app at 100% CPU on
  // the main thread, so a slow drag through 600 px is enough to freeze a
  // release build. Only the transition style follows the width; in-flight
  // transitions keep the style they started with.
  final tablet = context.isTablet;
  final reduceMotion = context.reduceMotion;
  final platformBuilder = _platformTransitionBuilder(context);
  final Duration duration = reduceMotion
      ? Duration.zero
      : tablet
      ? const Duration(milliseconds: 150)
      : platformBuilder.transitionDuration;
  final Duration reverseDuration = reduceMotion
      ? Duration.zero
      : tablet
      ? const Duration(milliseconds: 150)
      : platformBuilder.reverseTransitionDuration;
  return CustomTransitionPage(
    key: state.pageKey,
    child: pageChild,
    transitionDuration: duration,
    reverseTransitionDuration: reverseDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (tablet) {
        if (reduceMotion) {
          return ReducedRouteTransition(animation: animation, child: child);
        }
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      }
      // Phones keep the platform default, exactly as MaterialPage shows it.
      final route = ModalRoute.of(context);
      if (route is PageRoute) {
        return Theme.of(context).pageTransitionsTheme.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
      }
      return child;
    },
  );
}

PageTransitionsBuilder _platformTransitionBuilder(BuildContext context) {
  final theme = Theme.of(context);
  return theme.pageTransitionsTheme.builders[theme.platform] ??
      switch (theme.platform) {
        TargetPlatform.iOS ||
        TargetPlatform.macOS => const CupertinoPageTransitionsBuilder(),
        _ => const ZoomPageTransitionsBuilder(),
      };
}
