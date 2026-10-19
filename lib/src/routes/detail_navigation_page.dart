part of 'router_config.dart';

/// Page for routes that draw their own copy of the sidebar inside
/// [DetailNavigationShellScreen] (settings/account pages, source pages,
/// Upcoming), and for [DetailNavigationShellRoute] itself, which hosts the
/// series page and the other detail routes in its own Navigator.
///
/// On tablet and wider the sidebar is identical on both sides of the push, so
/// the default zoom would animate the sidebar along with the page and the app
/// looks like it jumps. A short fade keeps the sidebar visually still while
/// the content changes. Phones keep the default [MaterialPage] transition,
/// and reduced motion skips the fade entirely.
///
/// The width check runs when the page is built.
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
  if (!context.isTablet) {
    return MaterialPage(key: state.pageKey, child: pageChild);
  }
  if (context.reduceMotion) {
    return CustomTransitionPage(
      key: state.pageKey,
      child: pageChild,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          ReducedRouteTransition(animation: animation, child: child),
    );
  }
  return CustomTransitionPage(
    key: state.pageKey,
    child: pageChild,
    transitionDuration: const Duration(milliseconds: 150),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
  );
}
