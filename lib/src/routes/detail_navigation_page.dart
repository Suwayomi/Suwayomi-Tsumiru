part of 'router_config.dart';

/// Page for routes that draw their own copy of the sidebar inside
/// [DetailNavigationShellScreen] (settings/account pages, source pages,
/// Upcoming).
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
  final pageChild = DetailNavigationShellScreen(child: child);
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
