// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../routes/router_config.dart';
import '../../utils/extensions/custom_extensions.dart';
import '../../utils/motion/reduce_motion.dart';
import '../../utils/platform/platform_runtime.dart';
import '../shell/desktop_sidebar.dart';
import '../shell/sidebar_expanded.dart';
import '../tsumiru_logo.dart';
import 'desktop_title_bar.dart';

/// Height of the merged window bar: the title bar and the page toolbar as one
/// row. Matches the desktop page toolbars (64 px rows with 40 px controls).
const double kDesktopTopBarHeight = 64;

/// Gap between the brand block, the page toolbar and the window buttons.
const double kDesktopTopBarGap = 10;

/// Width of the minimise / maximise-restore / close cluster: three buttons at
/// window_manager's 46 px minimum width each.
const double kWindowButtonsWidth = 3 * 46;

/// Left inset on macOS: clears the native traffic lights, which AppKit keeps
/// at the top-left of the window when the title bar is hidden.
const double kMacOSTrafficLightsInset = 80;

/// Minimum search-field width the merged bar keeps before falling back to two
/// rows.
const double kTopBarSearchMinWidth = 200;

/// The merged bar replaces the title strip only in a desktop app running the
/// desktop layout (width >= 600 with a shortestSide >= 600). Web and phones are
/// unchanged.
bool useDesktopTopBar(BuildContext context) =>
    isDesktopPlatform && context.isDesktop;

/// The current route's matched location, or null outside a router (plain
/// widget tests that pump the bar on its own).
String? _matchedLocationOrNull(BuildContext context) {
  // Checked before GoRouterState.of: without a router above, `of` does not
  // throw — its route-walk keeps finding the plain MaterialPageRoute above a
  // nested Navigator and spins forever, hanging the frame. With a router
  // present the walk ends at the first go_router page as before.
  if (GoRouter.maybeOf(context) == null) return null;
  try {
    return GoRouterState.of(context).matchedLocation;
  } catch (_) {
    return null;
  }
}

/// The active leaf route's matched location: the top-most page's match from
/// the router's current configuration. The host bar sits in the shell above
/// its Navigator, so `GoRouterState.of` there reports the shell's own match,
/// which keeps the initial location after a push inside the shell (the shell
/// page is unchanged while the new page registers under the leaf's
/// location). Reading the router's current full match instead tracks pushes
/// and pops; without a router it falls back to the shell lookup above.
String _activeLeafLocation(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    try {
      return router.state.matchedLocation;
    } catch (_) {
      // Fall through to the shell lookup.
    }
  }
  return _matchedLocationOrNull(context) ?? '';
}

/// Window width at and above which the title bar and the page toolbar merge
/// into one 64 px bar. Below it the two rows stack: the 40 px title bar with
/// the toolbar below it. Built from the same widths and gaps as the bar
/// itself, like Tsumige's `oneBarBreakpoint`: the brand block (the sidebar's
/// current width), the page toolbar at its minimum, the window buttons (not
/// macOS) and one gap between each part.
double topBarBreakpoint({
  required double brandWidth,
  required double slotMinWidth,
  required bool isMacOS,
}) =>
    brandWidth +
    kDesktopTopBarGap +
    slotMinWidth +
    kDesktopTopBarGap +
    (isMacOS ? 0 : kWindowButtonsWidth + kDesktopTopBarGap);

/// Minimum width of a back-arrow-plus-title toolbar: the back button, a gap,
/// a short title that ellipsizes, plus one 48 px slot per action on the
/// right. Pages with a search field or wider controls pass their own value.
double titleTopBarSlotMinWidth(int actionCount) =>
    48.0 + kDesktopTopBarGap + 120.0 + actionCount * 48.0;

/// Minimum width of a search-field toolbar: a usable search box, one 48 px
/// slot per action and the gaps between the controls.
double searchTopBarSlotMinWidth(int actionCount) =>
    kTopBarSearchMinWidth +
    actionCount * (48.0 + kDesktopTopBarGap) +
    kDesktopTopBarGap;

/// Wraps a standard back-arrow title page for the desktop top bar: without
/// the merged bar [child] is returned unchanged; with it the page's AppBar
/// must be null and its toolbar shows in the shell bar instead. The page
/// passes the same leading, title and actions its AppBar uses (usually
/// [detailNavigationBackButton] for the leading). Pages whose title slot is
/// wider than back-plus-title (a search box) pass their own [minWidth].
Widget titleTopBarSlot({
  required bool topBar,
  Widget? leading,
  required Widget title,
  List<Widget> actions = const [],
  double? minWidth,
  required Widget child,
}) => topBar
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

/// The toolbar row for a search page: the search box left-aligned at up to
/// 720 px with the page's actions after it, matching the AppBar layout.
Widget desktopSearchSlotContent({
  required Widget search,
  required List<Widget> actions,
}) => Row(
  children: [
    Expanded(
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: search,
        ),
      ),
    ),
    ...actions,
  ],
);

/// The toolbar row for a back-arrow page: back button, title and the page's
/// actions, matching the AppBar layout. The page passes its own leading
/// (usually [detailNavigationBackButton]) because the bar sits outside the
/// page's Navigator, where the AppBar's implied back button cannot reach.
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
  Widget build(BuildContext context) => Row(
    children: [
      leading ?? const SizedBox.shrink(),
      Expanded(child: title),
      ...actions,
    ],
  );
}

/// One page's toolbar content, registered by route so the host always shows
/// the current route's toolbar: during a push both pages are mounted, and the
/// outgoing entry is ignored once the location moves on.
class TopBarSlotEntry {
  const TopBarSlotEntry({
    required this.content,
    required this.minWidth,
    this.slotKey = 'default',
  });

  /// The toolbar row, built by the page so it keeps the page's state (search
  /// focus, sort/filter panels anchored to their buttons, selection count).
  final Widget content;

  /// The toolbar's minimum width, for the one-bar/two-row breakpoint.
  final double minWidth;

  /// Distinguishes swapped toolbars on one route (normal vs selection mode).
  final Object slotKey;
}

class TopBarSlotRegistry extends Notifier<Map<String, TopBarSlotEntry>> {
  /// False once this container (and the registry with it) is disposed, so
  /// deferred slot removals can skip the dead notifier. A plain field: safe
  /// to read after disposal, unlike any notifier access.
  bool alive = true;

  @override
  Map<String, TopBarSlotEntry> build() {
    alive = true;
    ref.onDispose(() => alive = false);
    return const {};
  }

  void setEntry(String routeKey, TopBarSlotEntry entry) {
    state = {...state, routeKey: entry};
  }

  /// Removes [routeKey] only while it still holds [entry]: a route that
  /// re-registers after this slot unmounted (same location pushed again)
  /// publishes a new instance, which a stale removal must not clear.
  void removeEntry(String routeKey, TopBarSlotEntry entry) {
    if (!identical(state[routeKey], entry)) return;
    state = {...state}..remove(routeKey);
  }
}

final topBarSlotRegistryProvider =
    NotifierProvider<TopBarSlotRegistry, Map<String, TopBarSlotEntry>>(
      TopBarSlotRegistry.new,
    );

/// Registers [content] as the current route's toolbar for the desktop top
/// bar. Renders [child] unchanged; the content itself is shown by
/// [DesktopTopBar], keyed by route so the outgoing page's toolbar fades out
/// with the page and two toolbars never show at once.
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
  bool _scheduled = false;

  String _currentRouteKey() => _matchedLocationOrNull(context) ?? '';

  void _schedulePublish() {
    _routeKey = _currentRouteKey();
    _entry = TopBarSlotEntry(
      content: widget.content,
      minWidth: widget.minWidth,
      slotKey: widget.slotKey,
    );
    if (_scheduled) return;
    _scheduled = true;
    // Post-frame: the host bar is an ancestor that may still be building, and
    // publishing synchronously would setState it mid-build. The latest entry
    // wins: a second schedule before the frame only moves [_entry] forward.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final latest = _entry;
      if (latest == null) return;
      ref.read(topBarSlotRegistryProvider.notifier).setEntry(_routeKey, latest);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited lookups (the route location) are only legal here, not in
    // initState. The registry is captured too: `ref` is unusable in dispose.
    _registry = ref.read(topBarSlotRegistryProvider.notifier);
    _schedulePublish();
  }

  @override
  void didUpdateWidget(TopBarSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePublish();
  }

  @override
  void dispose() {
    // Deferred like publishing: unmounting runs inside the frame that
    // navigates away, where touching the provider throws, and a route that
    // re-registers meanwhile owns a newer entry the guard keeps.
    final registry = _registry;
    final routeKey = _routeKey;
    final entry = _entry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (entry == null) return;
      // Whole-tree teardown disposes the container with the tree; the
      // registry is gone, so there is nothing to clean.
      if (!registry.alive) return;
      registry.removeEntry(routeKey, entry);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The desktop window bar: `[brand block | page toolbar slot | window
/// buttons]` in one 64 px row, or the two-row fallback (40 px title bar plus
/// the toolbar row) when the window is too narrow. A [DragToMoveArea] sits
/// behind the controls across the whole bar, so every empty part drags the
/// window and double-clicking maximises/restores, as the title bar does.
class DesktopTopBar extends ConsumerWidget {
  const DesktopTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `GoRouter.of` does not subscribe, and the shell's own match never
    // changes on push/pop inside it, so rebuild off the router delegate and
    // read the leaf from the current configuration each time. Outside a
    // router (plain widget tests) the location never changes either.
    final delegate = GoRouter.maybeOf(context)?.routerDelegate;
    if (delegate == null) {
      // Outside a router (plain widget tests) both sides use the empty key.
      return _buildBar(context, ref, _matchedLocationOrNull(context) ?? '');
    }
    return ListenableBuilder(
      listenable: delegate,
      builder: (context, _) =>
          _buildBar(context, ref, _activeLeafLocation(context)),
    );
  }

  Widget _buildBar(BuildContext context, WidgetRef ref, String location) {
    final width = MediaQuery.sizeOf(context).width;
    final isMacOS = isMacOSRuntime;
    final preference = ref.watch(sidebarExpandedProvider).ifNull(true);
    final brandWidth = DesktopSidebar.widthFor(
      expanded: sidebarIsExpanded(context, preference),
      windowWidth: width,
    );
    final entry = ref.watch(topBarSlotRegistryProvider)[location];
    final merged =
        entry == null ||
        width >=
            topBarBreakpoint(
              brandWidth: brandWidth,
              slotMinWidth: entry.minWidth,
              isMacOS: isMacOS,
            );
    final theme = Theme.of(context);
    if (!merged) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DesktopTitleBar(),
          // The page toolbars are bare rows; the merged bar's surface has to
          // come from here so the row never goes transparent.
          Container(
            height: kDesktopTopBarHeight,
            color: theme.colorScheme.surface,
            child: _slotContent(context, entry, location),
          ),
        ],
      );
    }
    return Container(
      height: kDesktopTopBarHeight,
      color: theme.colorScheme.surface,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DragToMoveArea(child: SizedBox.expand()),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BrandBlock(width: brandWidth, isMacOS: isMacOS),
              const SizedBox(width: kDesktopTopBarGap),
              Expanded(child: _slotContent(context, entry, location)),
              if (!isMacOS) ...[
                const SizedBox(width: kDesktopTopBarGap),
                Center(
                  child: DesktopWindowButtons(brightness: theme.brightness),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _slotContent(
    BuildContext context,
    TopBarSlotEntry? entry,
    String location,
  ) {
    if (entry == null) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: context.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 150),
      child: Container(
        key: ValueKey('$location#${entry.slotKey}'),
        alignment: Alignment.center,
        child: entry.content,
      ),
    );
  }
}

/// The bar's left end, exactly the sidebar's current width so the column
/// lines up: logo plus name with the collapse chevron at its right end when
/// expanded, the logo alone (tap to expand) when collapsed. macOS shows the
/// traffic-lights inset instead of the logo and name. The width animates with
/// the same tween as the sidebar, so the two stay in sync.
class _BrandBlock extends ConsumerWidget {
  const _BrandBlock({required this.width, required this.isMacOS});

  final double width;
  final bool isMacOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(sidebarExpandedProvider).ifNull(true);
    final expanded = sidebarIsExpanded(context, preference);
    void toggle() =>
        ref.read(sidebarExpandedProvider.notifier).update(!preference);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: DesktopSidebar.widthFor(
          expanded: expanded,
          windowWidth: MediaQuery.sizeOf(context).width,
        ),
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
          child: isMacOS
              ? Row(
                  children: [
                    const SizedBox(width: kMacOSTrafficLightsInset),
                    if (showExpanded) ...[
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        tooltip: context.l10n.collapseSidebar,
                        onPressed: toggle,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ],
                )
              : showExpanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => const AboutRoute().push(context),
                        child: const TsumiruLogo(size: kBrandLogoSize),
                      ),
                      const SizedBox(width: kBrandGap),
                      Expanded(
                        child: Text('Tsumiru', style: brandNameStyle(context)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        tooltip: context.l10n.collapseSidebar,
                        onPressed: toggle,
                      ),
                    ],
                  ),
                )
              : Center(
                  child: IconButton(
                    icon: const TsumiruLogo(size: kBrandLogoSize),
                    tooltip: context.l10n.expandSidebar,
                    onPressed: toggle,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
        );
      },
    );
  }
}
