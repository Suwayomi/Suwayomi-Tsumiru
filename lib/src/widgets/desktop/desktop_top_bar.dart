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
  try {
    return GoRouterState.of(context).matchedLocation;
  } catch (_) {
    // No router above (plain widget tests pumping the bar on its own).
    return null;
  }
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

/// Whether the merged one-bar layout applies: the desktop top bar gate plus
/// enough width for the brand block and this page's toolbar at its minimum.
/// Pages hide their own top row and register it as a [TopBarSlot] exactly
/// when this is true, so the host and the page always agree.
bool useMergedTopBar(
  BuildContext context,
  WidgetRef ref, {
  required double slotMinWidth,
}) {
  if (!useDesktopTopBar(context)) return false;
  final width = MediaQuery.sizeOf(context).width;
  final preference = ref.watch(sidebarExpandedProvider).ifNull(true);
  return width >=
      topBarBreakpoint(
        brandWidth: DesktopSidebar.widthFor(
          expanded: sidebarIsExpanded(context, preference),
          windowWidth: width,
        ),
        slotMinWidth: slotMinWidth,
        isMacOS: isMacOSRuntime,
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
  @override
  Map<String, TopBarSlotEntry> build() => const {};

  void setEntry(String routeKey, TopBarSlotEntry entry) {
    state = {...state, routeKey: entry};
  }

  void removeEntry(String routeKey) {
    if (!state.containsKey(routeKey)) return;
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
  bool _scheduled = false;

  String _currentRouteKey() => _matchedLocationOrNull(context) ?? '';

  void _schedulePublish() {
    _routeKey = _currentRouteKey();
    if (_scheduled) return;
    _scheduled = true;
    // Post-frame: the host bar is an ancestor that may still be building, and
    // publishing synchronously would setState it mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      ref
          .read(topBarSlotRegistryProvider.notifier)
          .setEntry(
            _routeKey,
            TopBarSlotEntry(
              content: widget.content,
              minWidth: widget.minWidth,
              slotKey: widget.slotKey,
            ),
          );
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
    _registry.removeEntry(_routeKey);
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
    final width = MediaQuery.sizeOf(context).width;
    final isMacOS = isMacOSRuntime;
    final preference = ref.watch(sidebarExpandedProvider).ifNull(true);
    final brandWidth = DesktopSidebar.widthFor(
      expanded: sidebarIsExpanded(context, preference),
      windowWidth: width,
    );
    final location = _matchedLocationOrNull(context);
    final entry = location == null
        ? null
        : ref.watch(topBarSlotRegistryProvider)[location];
    final merged =
        entry == null ||
        width >=
            topBarBreakpoint(
              brandWidth: brandWidth,
              slotMinWidth: entry.minWidth,
              isMacOS: isMacOS,
            );
    if (!merged) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DesktopTitleBar(),
          SizedBox(
            height: kDesktopTopBarHeight,
            child: _slotContent(context, entry, location),
          ),
        ],
      );
    }
    final theme = Theme.of(context);
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
                  child: DesktopWindowButtons(
                    brightness: theme.brightness,
                  ),
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
    String? location,
  ) {
    if (entry == null || location == null) return const SizedBox.shrink();
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
