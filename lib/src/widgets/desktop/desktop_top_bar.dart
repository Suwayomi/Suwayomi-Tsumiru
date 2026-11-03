// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/settings/presentation/settings/settings_pane_scope.dart';
import '../../utils/desktop/linux_button_layout.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../../utils/motion/reduce_motion.dart';
import '../../utils/platform/platform_runtime.dart';
import '../shell/desktop_sidebar.dart';
import '../shell/sidebar_expanded.dart';
import 'desktop_brand.dart';
import 'desktop_page_frame.dart';
import 'desktop_title_bar.dart';

const double kDesktopTopBarHeight = 64;

const double kDesktopTopBarGap = 10;

// Compact desktop IconButtons use the 48 px touch target minus 8 px density.
const double kDesktopToolbarIconButtonExtent = 40;

const double kTopBarSearchMinWidth = 200;

const double kTopBarSearchPreferredWidth = 320;

/// Shared desktop-shell gate for merged bars, slots and page AppBar suppression.
bool showsMergedTopBar(BuildContext context) =>
    SettingsPaneScope.maybeOf(context) != null || context.usesDesktopShell;

/// Null outside a router.
String? _matchedLocationOrNull(BuildContext context) {
  // Check router presence first: GoRouterState.of can loop on a plain nested Navigator.
  if (GoRouter.maybeOf(context) == null) return null;
  try {
    return GoRouterState.of(context).matchedLocation;
  } catch (_) {
    return null;
  }
}

/// Read the active leaf from router configuration; the shell's own match stays unchanged on inner pushes.
String _activeLeafLocation(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    try {
      return router.state.matchedLocation;
    } catch (_) {
    }
  }
  return _matchedLocationOrNull(context) ?? '';
}

List<RouteMatchBase> _flattenMatches(List<RouteMatchBase> matches) {
  final flat = <RouteMatchBase>[];
  for (final match in matches) {
    flat.add(match);
    final List<RouteMatchBase> nested = match is ShellRouteMatch
        ? match.matches
        : match is ImperativeRouteMatch
        ? match.matches.matches
        : const <RouteMatchBase>[];
    flat.addAll(_flattenMatches(nested));
  }
  return flat;
}

// Window routes may have no slot, so resolve the visible page through the match stack.
String _resolveSlotKey(
  BuildContext context,
  Map<String, List<TopBarSlotEntry>> registry,
) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return _matchedLocationOrNull(context) ?? '';
  late final RouteMatchList configuration;
  try {
    configuration = router.routerDelegate.currentConfiguration;
  } catch (_) {
    return _activeLeafLocation(context);
  }
  final flat = _flattenMatches(configuration.matches);
  var start = 0;
  // Beneath a non-opaque window the visible page sits below this page in the stack.
  var beneathVisible = false;
  final ownRoute = ModalRoute.of(context);
  if (ownRoute != null) {
    final ownPages = ownRoute.navigator?.widget.pages ?? const <Page>[];
    final ownIndex = ownPages.indexWhere(
      (page) => identical(page, ownRoute.settings),
    );
    if (ownIndex >= 0) {
      final ownKey = ownPages[ownIndex].key;
      final flatIndex = flat.lastIndexWhere(
        (match) => match.pageKey == ownKey,
      );
      if (flatIndex >= 0) start = flatIndex;
      beneathVisible =
          ownIndex < ownPages.length - 1 &&
          ownPages
              .skip(ownIndex + 1)
              .every((page) => page is CustomTransitionPage && !page.opaque);
    }
  }
  for (var i = flat.length - 1; i >= start; i--) {
    final entries = registry[flat[i].matchedLocation];
    if (entries != null && entries.isNotEmpty) return flat[i].matchedLocation;
  }
  if (beneathVisible) {
    for (var i = start - 1; i >= 0; i--) {
      final entries = registry[flat[i].matchedLocation];
      if (entries != null && entries.isNotEmpty) {
        return flat[i].matchedLocation;
      }
    }
  }
  return _activeLeafLocation(context);
}

double titleTopBarSlotMinWidth(int actionCount) =>
    48.0 + kDesktopTopBarGap + 120.0 + actionCount * 48.0;

double searchTopBarSlotMinWidth(int actionCount, [double leadingWidth = 0]) =>
    kTopBarSearchMinWidth +
    2 * kDesktopToolbarSlotHPadding +
    leadingWidth +
    actionCount * 48.0 +
    (actionCount + (leadingWidth > 0 ? 1 : 0)) * kDesktopTopBarGap;

BoxConstraints settingsPageConstraints(
  BuildContext context, {
  double maxWidth = kDesktopSettingsMaxWidth,
}) => BoxConstraints(
  maxWidth: SettingsPaneScope.maybeOf(context) == null
      ? maxWidth
      : double.infinity,
);

EdgeInsets? settingsPagePadding(
  BuildContext context, [
  EdgeInsetsGeometry? padding,
]) {
  final pane = SettingsPaneScope.maybeOf(context);
  if (pane == null) return padding?.resolve(Directionality.of(context));
  return EdgeInsets.only(
    left: 20,
    right: (pane.width - 740).clamp(0, double.infinity),
  ).add(padding ?? EdgeInsets.zero).resolve(Directionality.of(context));
}

/// With the merged bar, suppress the page AppBar and provide its toolbar; otherwise return child unchanged.
Widget titleTopBarSlot({
  required bool topBar,
  Widget? leading,
  required Widget title,
  List<Widget> actions = const [],
  double? minWidth,
  required Widget child,
}) => Builder(
  builder: (context) {
    final pane = SettingsPaneScope.maybeOf(context);
    if (pane != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  if (pane.nested)
                    leading ?? BackButton(onPressed: pane.onBack),
                  Expanded(
                    child: DefaultTextStyle(
                      style: Theme.of(context).textTheme.titleLarge!,
                      child: pane.tabs != null && !pane.nested
                          ? Text(context.l10n.server)
                          : title,
                    ),
                  ),
                  ...actions,
                  CloseButton(onPressed: pane.onClose),
                ],
              ),
            ),
          ),
          if (pane.tabs != null) pane.tabs!,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: child,
            ),
          ),
        ],
      );
    }
    return topBar
        ? TopBarSlot(
            content: DesktopTitleSlot(
              leading: leading,
              title: title,
              actions: actions,
            ),
            minWidth: minWidth ?? titleTopBarSlotMinWidth(actions.length),
            child: child,
          )
        : child;
  },
);

const double kDesktopToolbarSlotHPadding = 12.0;

const double kDesktopSearchMaxWidth = 600.0;

Widget desktopToolbarRow({
  required Widget search,
  required List<Widget> actions,
  Widget? leading,
  int spacedActionCount = 0,
  double gap = kDesktopTopBarGap,
}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: kDesktopToolbarSlotHPadding),
  child: Row(
    spacing: gap,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      ?leading,
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kTopBarSearchPreferredWidth,
            ),
            child: _desktopToolbarIconTheme(search),
          ),
        ),
      ),
      ...actions.take(spacedActionCount),
      if (actions.length > spacedActionCount)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions.skip(spacedActionCount))
              _desktopToolbarIconButton(action),
          ],
        ),
    ],
  ),
);

Widget _desktopToolbarIconButton(Widget child) => ConstrainedBox(
  constraints: const BoxConstraints(
    maxWidth: kDesktopToolbarIconButtonExtent,
    maxHeight: kDesktopToolbarIconButtonExtent,
  ),
  child: _desktopToolbarIconTheme(child),
);

Widget _desktopToolbarIconTheme(Widget child) => IconButtonTheme(
  data: IconButtonThemeData(
    style: IconButton.styleFrom(
      fixedSize: const Size.square(kDesktopToolbarIconButtonExtent),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  ),
  child: child,
);

Widget desktopSearchSlotContent({
  Widget? leading,
  required Widget search,
  required List<Widget> actions,
  int spacedActionCount = 0,
}) => desktopToolbarRow(
  leading: leading == null ? null : _desktopToolbarIconButton(leading),
  search: search,
  actions: actions,
  spacedActionCount: spacedActionCount,
);

/// Supply the page's back button: this toolbar sits outside its Navigator.
class DesktopTitleSlot extends StatelessWidget {
  const DesktopTitleSlot({
    super.key,
    this.leading,
    required this.title,
    this.actions = const [],
  });

  final Widget? leading;
  final Widget title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => _desktopToolbarIconTheme(
    Row(
      children: [
        if (leading != null) _desktopToolbarIconButton(leading!),
        Expanded(child: title),
        ...actions,
      ],
    ),
  );
}

/// Route-keyed toolbars stack newest-last so duplicate-location pushes keep separate entries.
class TopBarSlotEntry {
  const TopBarSlotEntry({
    required this.content,
    required this.minWidth,
    this.slotKey = 'default',
  });

  final Widget content;

  final double minWidth;

  /// Distinguishes normal and selection toolbars on the same route.
  final Object slotKey;
}

class TopBarSlotRegistry extends Notifier<Map<String, List<TopBarSlotEntry>>> {
  /// Plain disposal flag remains safe to read after notifier disposal.
  bool alive = true;

  @override
  Map<String, List<TopBarSlotEntry>> build() {
    alive = true;
    ref.onDispose(() => alive = false);
    return const {};
  }

  /// Replace only this slot instance; duplicate locations retain earlier registrations.
  void setEntry(
    String routeKey,
    TopBarSlotEntry? previous,
    TopBarSlotEntry entry,
  ) {
    final entries = [...?state[routeKey]];
    if (previous != null) {
      entries.removeWhere((candidate) => identical(candidate, previous));
    }
    entries.add(entry);
    state = {...state, routeKey: entries};
  }

  /// Remove only the still-registered instance so stale removals cannot clear replacements.
  void removeEntry(String routeKey, TopBarSlotEntry entry) {
    final entries = state[routeKey];
    if (entries == null ||
        !entries.any((candidate) => identical(candidate, entry))) {
      return;
    }
    final next = [...entries]
      ..removeWhere((candidate) => identical(candidate, entry));
    if (next.isEmpty) {
      state = {...state}..remove(routeKey);
    } else {
      state = {...state, routeKey: next};
    }
  }
}

final topBarSlotRegistryProvider =
    NotifierProvider<TopBarSlotRegistry, Map<String, List<TopBarSlotEntry>>>(
      TopBarSlotRegistry.new,
    );

/// Count displayed bars, not mounted shells: transitions overlap and offstage shells need no bar.
class MergedTopBarRegistry extends Notifier<int> {
  /// Plain disposal flag remains safe to read after notifier disposal.
  bool alive = true;

  @override
  int build() {
    alive = true;
    ref.onDispose(() => alive = false);
    return 0;
  }

  void show() {
    if (!alive) return;
    state = state + 1;
  }

  void hide() {
    if (!alive || state == 0) return;
    state = state - 1;
  }
}

final mergedTopBarRegistryProvider =
    NotifierProvider<MergedTopBarRegistry, int>(MergedTopBarRegistry.new);

/// Register content by route; child stays in place while the host shows the active toolbar.
class TopBarSlot extends ConsumerStatefulWidget {
  const TopBarSlot({
    super.key,
    required this.content,
    required this.minWidth,
    this.slotKey = 'default',
    required this.child,
  });

  final Widget content;
  final double minWidth;
  final Object slotKey;
  final Widget child;

  @override
  ConsumerState<TopBarSlot> createState() => _TopBarSlotState();
}

class _TopBarSlotState extends ConsumerState<TopBarSlot> {
  late String _routeKey;
  late TopBarSlotRegistry _registry;
  TopBarSlotEntry? _entry;
  String _publishedKey = '';
  TopBarSlotEntry? _publishedEntry;
  bool _scheduled = false;
  bool _covered = false;
  List<ModalRoute> _watchedRoutes = const [];

  // Publish under the owning route so windows without slots can retain the visible toolbar.
  String _currentRouteKey() => _matchedLocationOrNull(context) ?? '';

  List<ModalRoute> _routeChain() {
    final chain = <ModalRoute>[];
    var routeContext = context;
    while (true) {
      final route = ModalRoute.of(routeContext);
      if (route == null) break;
      chain.add(route);
      final navigator = route.navigator;
      if (navigator == null) break;
      routeContext = navigator.context;
    }
    return chain;
  }

  // An opaque page above hides this slot; dialogs are not pages.
  bool _routeCoveredByOpaque(ModalRoute route) {
    if (route.isCurrent) return false;
    final pages = route.navigator?.widget.pages ?? const <Page>[];
    final index = pages.indexWhere((page) => identical(page, route.settings));
    if (index < 0) return false;
    for (final page in pages.skip(index + 1)) {
      if (page is! CustomTransitionPage || page.opaque) return true;
    }
    return false;
  }

  // A covered route with only window pages above it is still visible.
  bool _routeHasWindowAbove(ModalRoute route) {
    if (route.isCurrent) return false;
    final pages = route.navigator?.widget.pages ?? const <Page>[];
    final index = pages.indexWhere((page) => identical(page, route.settings));
    if (index < 0) return false;
    return pages
        .skip(index + 1)
        .any((page) => page is CustomTransitionPage && !page.opaque);
  }

  ({bool covered, bool coveredOpaque}) _coverStateOf(List<ModalRoute> chain) {
    var covered = false;
    var coveredOpaque = false;
    for (final route in chain) {
      if (_routeCoveredByOpaque(route)) {
        covered = true;
        coveredOpaque = true;
      } else if (!route.isCurrent && !_routeHasWindowAbove(route)) {
        covered = true;
      }
    }
    return (covered: covered, coveredOpaque: coveredOpaque);
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleCoverChanged);
  }

  // Dialogs/popups never animate the routes below them, so republish through build when focus moves.
  void _handleCoverChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_coverStateOf(_routeChain()).covered == _covered) return;
      setState(() {});
    });
  }

  void _onCoverStatus(AnimationStatus _) => _handleCoverChanged();

  void _syncRouteWatch(List<ModalRoute> chain) {
    if (chain.length == _watchedRoutes.length &&
        Iterable.generate(
          chain.length,
        ).every((i) => identical(chain[i], _watchedRoutes[i]))) {
      return;
    }
    _unwatchRoutes();
    _watchedRoutes = List.of(chain);
    for (final route in _watchedRoutes) {
      route.animation?.addStatusListener(_onCoverStatus);
      route.secondaryAnimation?.addStatusListener(_onCoverStatus);
    }
  }

  void _unwatchRoutes() {
    for (final route in _watchedRoutes) {
      route.animation?.removeStatusListener(_onCoverStatus);
      route.secondaryAnimation?.removeStatusListener(_onCoverStatus);
    }
    _watchedRoutes = const [];
  }

  void _scheduleRemoval() {
    final previous = _publishedEntry;
    if (previous == null) return;
    final routeKey = _publishedKey;
    _publishedEntry = null;
    _publishedKey = '';
    final registry = _registry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!registry.alive) return;
      registry.removeEntry(routeKey, previous);
    });
  }

  void _schedulePublish() {
    final chain = _routeChain();
    final cover = _coverStateOf(chain);
    _syncRouteWatch(chain);
    _covered = cover.covered;
    // Opaque pages hide this slot, so drop its entry; dialogs keep it.
    if (cover.coveredOpaque) {
      _scheduleRemoval();
      return;
    }
    if (!TickerMode.valuesOf(context).enabled) return;
    if (cover.covered) return;
    _routeKey = _currentRouteKey();
    _entry = TopBarSlotEntry(
      content: widget.content,
      minWidth: widget.minWidth,
      slotKey: widget.slotKey,
    );
    if (_scheduled) return;
    _scheduled = true;
    // Publish post-frame to avoid rebuilding the ancestor mid-build; replace only this slot instance.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final latest = _entry;
      if (latest == null) return;
      final notifier = ref.read(topBarSlotRegistryProvider.notifier);
      final previous = _publishedEntry;
      if (previous != null && _publishedKey != _routeKey) {
        notifier.removeEntry(_publishedKey, previous);
      }
      notifier.setEntry(
        _routeKey,
        _publishedKey == _routeKey ? previous : null,
        latest,
      );
      _publishedKey = _routeKey;
      _publishedEntry = latest;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited lookups belong here; capture the registry because ref is unusable in dispose.
    _registry = ref.read(topBarSlotRegistryProvider.notifier);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleCoverChanged);
    _unwatchRoutes();
    // Defer provider changes during unmount; remove only this slot's published instance.
    final registry = _registry;
    final routeKey = _publishedKey;
    final entry = _publishedEntry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (entry == null) return;
      if (!registry.alive) return;
      registry.removeEntry(routeKey, entry);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _schedulePublish();
    return widget.child;
  }
}

class DesktopTopBar extends ConsumerStatefulWidget {
  const DesktopTopBar({super.key});

  @override
  ConsumerState<DesktopTopBar> createState() => _DesktopTopBarState();
}

class _DesktopTopBarState extends ConsumerState<DesktopTopBar> {
  late MergedTopBarRegistry _registry;
  bool _scheduled = false;
  bool _shown = false;

  /// Track displayed routes: a shell can remain mounted offstage beneath the reader.
  bool _isBarVisible() {
    final route = ModalRoute.of(context);
    final pages = route?.navigator?.widget.pages ?? const <Page>[];
    final index = pages.indexWhere((page) => identical(page, route?.settings));
    final visibleThroughOverlay =
        index >= 0 &&
        pages
            .skip(index + 1)
            .every((page) => page is CustomTransitionPage && !page.opaque);
    return ((route?.isCurrent ?? true) || visibleThroughOverlay) &&
        TickerMode.valuesOf(context).enabled;
  }

  bool _wantVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Capture the registry before disposal; publish displayed state post-frame to avoid ancestor setState.
    _registry = ref.read(mergedTopBarRegistryProvider.notifier);
    _wantVisible = _isBarVisible();
    // Reconcile only visibility changes so registrations stay balanced.
    if (_scheduled || _wantVisible == _shown) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (_wantVisible && !_shown) {
        _shown = true;
        _registry.show();
      } else if (!_wantVisible && _shown) {
        _shown = false;
        _registry.hide();
      }
    });
  }

  @override
  void dispose() {
    // Defer removal during unmount and balance only registrations that were actually published.
    final registry = _registry;
    final wasShown = _shown;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (wasShown) registry.hide();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // GoRouter.of does not subscribe; listen to the delegate for inner pushes and pops.
    final delegate = GoRouter.maybeOf(context)?.routerDelegate;
    if (delegate == null) {
      return _buildBar(context, ref, _matchedLocationOrNull(context) ?? '');
    }
    return ListenableBuilder(
      listenable: delegate,
      builder: (context, _) => _buildBar(
        context,
        ref,
        _resolveSlotKey(context, ref.watch(topBarSlotRegistryProvider)),
      ),
    );
  }

  Widget _buildBar(BuildContext context, WidgetRef ref, String location) {
    final native = isDesktopPlatform;
    final isMacOS = native && isMacOSRuntime;
    final preference = ref.watch(sidebarExpandedProvider).ifNull(true);
    final expanded = sidebarIsExpanded(context, preference);
    final stacked = ref.watch(topBarSlotRegistryProvider)[location];
    final entry = (stacked == null || stacked.isEmpty) ? null : stacked.last;
    final visible = _isBarVisible();
    final theme = Theme.of(context);
    final linuxButtons = isLinuxRuntime && native;
    return ValueListenableBuilder<LinuxButtonLayout>(
      valueListenable: linuxButtonLayoutNotifier,
      builder: (context, layout, _) {
        final linuxLeading =
            linuxButtons ? layout.leading : const <LinuxWindowButton>[];
        // macOS traffic lights and Linux leading buttons free the brand block.
        final brandInSidebar = isMacOS || linuxLeading.isNotEmpty;
        final brandWidth = DesktopSidebar.widthFor(
          expanded: expanded,
          isMacOS: isMacOS,
          leadingWidth: linuxWindowButtonsWidth(linuxLeading.length),
        );
        return Container(
          height: kDesktopTopBarHeight,
          color: theme.colorScheme.surface,
          child: Stack(
            children: [
              if (native)
                const Positioned.fill(
                  child: DragToMoveArea(child: SizedBox.expand()),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BrandBlock(
                    width: brandWidth,
                    brandInSidebar: brandInSidebar,
                    linuxLeading: linuxLeading,
                  ),
                  const SizedBox(width: kDesktopTopBarGap),
                  Expanded(
                    child: _slotContent(
                      context,
                      entry,
                      location,
                      visible: visible,
                    ),
                  ),
                  if (!isMacOS &&
                      native &&
                      (!linuxButtons || layout.trailing.isNotEmpty)) ...[
                    const SizedBox(width: kDesktopTopBarGap),
                    Center(
                      child: DesktopWindowButtons(
                        brightness: theme.brightness,
                        linuxButtons: linuxButtons ? layout.trailing : null,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _slotContent(
    BuildContext context,
    TopBarSlotEntry? entry,
    String location, {
    required bool visible,
  }) {
    if (entry == null || !visible) return const SizedBox.shrink();
    final key = '$location#${entry.slotKey}';
    return AnimatedSwitcher(
      duration: context.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 150),
      // Clamp the one-frame unbounded width during entry switches.
      child: LimitedBox(
        key: ValueKey(key),
        maxWidth: entry.minWidth,
        child: Container(
          alignment: Alignment.center,
          child: entry.content,
        ),
      ),
    );
  }
}

/// Match the animated sidebar width; free when the brand lives in the sidebar.
class _BrandBlock extends ConsumerWidget {
  const _BrandBlock({
    required this.width,
    required this.brandInSidebar,
    this.linuxLeading = const [],
  });

  final double width;
  final bool brandInSidebar;
  final List<LinuxWindowButton> linuxLeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(sidebarExpandedProvider).ifNull(true);
    final expanded = sidebarIsExpanded(context, preference);
    void toggle() =>
        ref.read(sidebarExpandedProvider.notifier).update(!preference);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: DesktopSidebar.widthFor(expanded: expanded),
        end: width,
      ),
      duration: context.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      builder: (context, animatedWidth, _) {
        final showExpanded =
            animatedWidth >
            (DesktopSidebar.expandedWidth + DesktopSidebar.collapsedWidth) / 2;
        return SizedBox(
          width: animatedWidth,
          height: kDesktopTopBarHeight,
          child: brandInSidebar
              ? linuxLeading.isEmpty
                    ? const SizedBox.expand()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: DesktopWindowButtons(
                          brightness: Theme.of(context).brightness,
                          linuxButtons: linuxLeading,
                          leading: true,
                        ),
                      )
              : showExpanded
              ? DesktopBrandRow(onCollapse: toggle)
              : Center(
                  child: sidebarCanExpand(context)
                      ? DesktopBrandExpandButton(onExpand: toggle)
                      : const SizedBox.shrink(),
                ),
        );
      },
    );
  }
}
