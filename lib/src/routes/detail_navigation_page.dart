part of 'router_config.dart';

/// Fade sidebar-bearing pages on wide layouts to keep the sidebar visually still.
Page<void> detailNavigationPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  return _detailNavigationPage(
    context,
    state,
    SettingsPaneScope.maybeOf(context) == null
        ? DetailNavigationShellScreen(child: child)
        : SettingsWindowPageBody(child: child),
  );
}

/// Outer shell pages also fade because their sidebars move with the page.
Page<void> navigationShellPage(
  BuildContext context,
  GoRouterState state,
  Widget shell,
) {
  return _detailNavigationPage(context, state, shell);
}

/// Fade the shell itself; inner pushes leave its sidebar outside the animation.
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
  // Keep page type and key independent of width so resizing preserves route identity.
  final tablet = context.windowSizeClass >= WindowSizeClass.medium;
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
