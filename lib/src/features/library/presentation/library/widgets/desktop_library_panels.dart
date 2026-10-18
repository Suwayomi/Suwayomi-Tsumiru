// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/motion/reduce_motion.dart';
import '../../../../../widgets/custom_checkbox_list_tile.dart';
import '../../../../../widgets/manga_cover/providers/manga_cover_providers.dart';
import '../../../../tracking/data/tracker_repository.dart';
import '../../../domain/library_group.dart';
import '../controller/library_controller.dart';
import '../controller/library_grouping.dart';
import 'library_filter_content.dart';
import 'library_filter_segments.dart';
import 'library_manga_badges.dart';

/// Anchors a dropdown menu to [rect], in overlay coordinates. Same mechanism
/// the series page uses for its chapter filter
/// (`big_screen_manga_details.dart`): the menu's top edge sits 6 px below the
/// button, no scrim, Esc closes only the panel.
RelativeRect menuAnchorForRect(BuildContext context, Rect rect) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(rect, Offset.zero & overlay.size);
}

/// Positions [child] (a fixed-size panel) from an anchor rect the same way
/// the series page positions its filter menu: the panel's top edge sits 6 px
/// below the button and its right edge aligns with the button's right edge,
/// clamped into the overlay with an 8 px margin.
class _LibraryPanelLayout extends SingleChildLayoutDelegate {
  _LibraryPanelLayout(this.anchor);

  /// Button rect in overlay coordinates (zero size: only its edges matter).
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Mirror the menu rule: grow toward the side with more room.
    final fromRight = size.width - (anchor.left + anchor.width);
    var x = anchor.left > fromRight
        ? anchor.left + anchor.width - childSize.width
        : anchor.left;
    var y = anchor.top;
    x = x.clamp(
      8.0,
      (size.width - childSize.width - 8.0).clamp(8.0, size.width),
    );
    y = y.clamp(
      8.0,
      (size.height - childSize.height - 8.0).clamp(8.0, size.height),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_LibraryPanelLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

/// Anchored dropdown route: the same presentation the series page gets from
/// `showMenu` (anchored under the button, rounded 14, no scrim, focus
/// returns to the button on close, Esc closes only the panel) without
/// `showMenu`'s 280 px menu width cap, which cannot host a 720 px panel.
class _LibraryPanelRoute extends PopupRoute<void> {
  _LibraryPanelRoute({
    required this.position,
    required this.panelSize,
    required this.panel,
    required this.capturedThemes,
    required this.barrierLabel,
    this.popUpAnimationStyle,
  });

  final RelativeRect position;
  final Size panelSize;
  final Widget panel;
  final CapturedThemes capturedThemes;
  final AnimationStyle? popUpAnimationStyle;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      popUpAnimationStyle?.duration ?? const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Same anchor math as the series page filter: right edge under
          // the button's right edge, 6 px below it.
          final overlay = Offset.zero & constraints.biggest;
          final anchor = position.toRect(overlay);
          return CustomSingleChildLayout(
            delegate: _LibraryPanelLayout(anchor),
            child: capturedThemes.wrap(
              Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.of(context).pop();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: SizedBox.fromSize(
                  size: panelSize,
                  child: Material(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: MediaQuery(
                      data: mediaQuery.copyWith(padding: EdgeInsets.zero),
                      child: panel,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: popUpAnimationStyle?.curve ?? Curves.easeOut,
      reverseCurve: popUpAnimationStyle?.reverseCurve ?? Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

Future<void> _openPanel({
  required BuildContext context,
  required GlobalKey buttonKey,
  required FocusNode focusNode,
  required double panelWidth,
  required double panelHeight,
  required Widget child,
}) async {
  final box = buttonKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final navigator = Navigator.of(context);
  await navigator.push(
    _LibraryPanelRoute(
      position: menuAnchorForRect(
        context,
        Rect.fromLTWH(rect.right - panelWidth, rect.bottom + 6, 0, 0),
      ),
      panelSize: Size(panelWidth, panelHeight),
      panel: child,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      popUpAnimationStyle: context.motionStyle,
    ),
  );
  if (context.mounted) focusNode.requestFocus();
}

/// Opens the desktop Filter panel anchored under the toolbar's Filter
/// button: 720 px, two columns, changes apply live.
Future<void> showLibraryFilterPanel({
  required BuildContext context,
  required GlobalKey buttonKey,
  required FocusNode focusNode,
}) => _openPanel(
  context: context,
  buttonKey: buttonKey,
  focusNode: focusNode,
  panelWidth: 720,
  panelHeight: 600,
  child: const DesktopLibraryFilterPanel(),
);

/// Opens the desktop Display panel anchored under the toolbar's Display
/// button: 760 px, three columns, changes apply live.
Future<void> showLibraryDisplayPanel({
  required BuildContext context,
  required GlobalKey buttonKey,
  required FocusNode focusNode,
}) => _openPanel(
  context: context,
  buttonKey: buttonKey,
  focusNode: focusNode,
  panelWidth: 760,
  panelHeight: 600,
  child: const DesktopLibraryDisplayPanel(),
);

/// Desktop Filter panel body: header row plus the shared filter content in
/// two columns. The tag list scrolls inside a fixed max height so the panel
/// itself never scrolls.
class DesktopLibraryFilterPanel extends StatelessWidget {
  const DesktopLibraryFilterPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: LibraryFilterContent(twoColumns: true),
    );
  }
}

/// Desktop Display panel body: three columns of radio lists and checkboxes,
/// no segmented switches.
class DesktopLibraryDisplayPanel extends StatelessWidget {
  const DesktopLibraryDisplayPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.display,
            style: context.theme.textTheme.titleMedium,
          ),
          const Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _DisplayColumn()),
                SizedBox(width: 24),
                Expanded(child: _BadgesColumn()),
                SizedBox(width: 24),
                Expanded(child: _GroupColumn()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Col 1: Display Mode radios, then the cover checkboxes.
class _DisplayColumn extends ConsumerWidget {
  const _DisplayColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final selectedMode =
        displayMode ?? DBKeys.libraryDisplayMode.initial as DisplayMode;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilterSectionHeading(context.l10n.displayMode),
          RadioGroup<DisplayMode>(
            groupValue: selectedMode,
            onChanged: (mode) =>
                ref.read(libraryDisplayModeProvider.notifier).update(mode),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in DisplayMode.libraryDisplayList)
                  RadioListTile<DisplayMode>(
                    value: mode,
                    title: Text(mode.toLibraryLocale(context)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          if (selectedMode == DisplayMode.comfortableGrid ||
              selectedMode == DisplayMode.list ||
              selectedMode == DisplayMode.descriptiveList)
            CustomCheckboxListTile(
              title: context.l10n.limitTitleLines,
              provider: limitTitleLinesProvider,
              onChanged: ref.read(limitTitleLinesProvider.notifier).update,
            ),
          CustomCheckboxListTile(
            title: context.l10n.outlineOnCovers,
            provider: outlineOnCoversProvider,
            onChanged: ref.read(outlineOnCoversProvider.notifier).update,
          ),
        ],
      ),
    );
  }
}

/// Col 2: Badges (unread mode radios, badge checkboxes, badge layout) then
/// Grid style radios.
class _BadgesColumn extends ConsumerWidget {
  const _BadgesColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadMode =
        ref.watch(unreadBadgeStyleProvider) ?? UnreadBadgeMode.count;
    final gridStyle =
        ref.watch(libraryGridStyleKeyProvider) ?? LibraryGridStyle.uniform;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilterSectionHeading(context.l10n.badges),
          FilterSectionHeading(context.l10n.unreadBadgeMode),
          RadioGroup<UnreadBadgeMode>(
            groupValue: unreadMode,
            onChanged: (mode) =>
                ref.read(unreadBadgeStyleProvider.notifier).update(mode),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in UnreadBadgeMode.values)
                  RadioListTile<UnreadBadgeMode>(
                    value: mode,
                    title: Text(mode.toLocale(context)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          CustomCheckboxListTile(
            title: context.l10n.downloaded,
            provider: downloadedBadgeProvider,
            onChanged: ref.read(downloadedBadgeProvider.notifier).update,
          ),
          CustomCheckboxListTile(
            title: context.l10n.onDevice,
            provider: onDeviceBadgeProvider,
            onChanged: ref.read(onDeviceBadgeProvider.notifier).update,
          ),
          CustomCheckboxListTile(
            title: context.l10n.readProgressBar,
            provider: readProgressBarProvider,
            onChanged: ref.read(readProgressBarProvider.notifier).update,
          ),
          CustomCheckboxListTile(
            title: context.l10n.continueReadingButton,
            provider: showContinueReadingButtonProvider,
            onChanged: ref
                .read(showContinueReadingButtonProvider.notifier)
                .update,
          ),
          CustomCheckboxListTile(
            title: context.l10n.sourceBadge,
            provider: sourceBadgeProvider,
            onChanged: ref.read(sourceBadgeProvider.notifier).update,
          ),
          CustomCheckboxListTile(
            title: context.l10n.languageBadge,
            provider: languageBadgeProvider,
            onChanged: ref.read(languageBadgeProvider.notifier).update,
          ),
          FilterSectionHeading(context.l10n.badgeLayout),
          const BadgeLayoutList(),
          FilterSectionHeading(context.l10n.gridStyle),
          RadioGroup<LibraryGridStyle>(
            groupValue: gridStyle,
            onChanged: (style) =>
                ref.read(libraryGridStyleKeyProvider.notifier).update(style),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final style in LibraryGridStyle.values)
                  RadioListTile<LibraryGridStyle>(
                    value: style,
                    secondary: Icon(style.icon, size: 18),
                    title: Text(style.toLocale(context)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Col 3: Group radios, Group display radios, then every leftover setting
/// from today's tabs: columns per orientation, list size, category tabs,
/// item counts and hidden categories.
class _GroupColumn extends ConsumerWidget {
  const _GroupColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(libraryGroupTypeProvider) ?? kDefaultLibraryGroupType;
    final style =
        ref.watch(libraryGroupStyleKeyProvider) ?? LibraryGroupStyle.tabs;
    final hasTrackers =
        ref.watch(loggedInTrackersProvider).value?.isNotEmpty ?? false;
    final isGrid =
        (ref.watch(libraryDisplayModeProvider) ??
                DBKeys.libraryDisplayMode.initial as DisplayMode)
            .isGrid;
    final portraitCols = ref.watch(libraryPortraitColumnsProvider) ?? 0;
    final landscapeCols = ref.watch(libraryLandscapeColumnsProvider) ?? 0;
    final listScale =
        ref.watch(libraryListScaleProvider) ??
        DBKeys.listScale.initial as double;

    String groupLabel(int type) => switch (type) {
      LibraryGroup.byDefault => context.l10n.groupByDefault,
      LibraryGroup.byTag => context.l10n.groupByTag,
      LibraryGroup.bySource => context.l10n.groupBySource,
      LibraryGroup.byStatus => context.l10n.groupByStatus,
      LibraryGroup.byTrackStatus => context.l10n.groupByTrackStatus,
      LibraryGroup.byLanguage => context.l10n.groupByLanguage,
      _ => context.l10n.groupUngrouped,
    };

    final isGrouped = LibraryGroup.isGrouped(current);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilterSectionHeading(context.l10n.group),
          RadioGroup<int>(
            groupValue: current,
            onChanged: (value) =>
                ref.read(libraryGroupTypeProvider.notifier).update(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final type in LibraryGroup.all)
                  if (type != LibraryGroup.byTrackStatus || hasTrackers)
                    RadioListTile<int>(
                      value: type,
                      title: Text(groupLabel(type)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
              ],
            ),
          ),
          if (isGrouped) ...[
            FilterSectionHeading(context.l10n.groupStyle),
            RadioGroup<LibraryGroupStyle>(
              groupValue: style,
              onChanged: (value) =>
                  ref.read(libraryGroupStyleKeyProvider.notifier).update(value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<LibraryGroupStyle>(
                    value: LibraryGroupStyle.tabs,
                    title: Text(context.l10n.groupStyleTabs),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<LibraryGroupStyle>(
                    value: LibraryGroupStyle.headers,
                    title: Text(context.l10n.groupStyleSections),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (style == LibraryGroupStyle.tabs)
              CustomCheckboxListTile(
                title: context.l10n.categoryTabs,
                provider: categoryTabsProvider,
                onChanged: ref.read(categoryTabsProvider.notifier).update,
              )
            else
              CustomCheckboxListTile(
                title: context.l10n.sectionHeadersShowAllCategories,
                provider: sectionHeadersShowAllCategoriesProvider,
                onChanged: ref
                    .read(sectionHeadersShowAllCategoriesProvider.notifier)
                    .update,
              ),
            if (current == LibraryGroup.byDefault)
              CustomCheckboxListTile(
                title: context.l10n.showHiddenCategories,
                provider: showHiddenCategoriesProvider,
                onChanged: ref
                    .read(showHiddenCategoriesProvider.notifier)
                    .update,
              ),
            CustomCheckboxListTile(
              title: context.l10n.categoryNumberOfItems,
              provider: categoryNumberOfItemsProvider,
              onChanged: ref
                  .read(categoryNumberOfItemsProvider.notifier)
                  .update,
            ),
          ],
          if (isGrid) ...[
            FilterSectionHeading(context.l10n.libraryColumnsPortrait),
            _ColumnsSlider(
              value: portraitCols,
              onChanged: (value) => ref
                  .read(libraryPortraitColumnsProvider.notifier)
                  .update(value),
            ),
            FilterSectionHeading(context.l10n.libraryColumnsLandscape),
            _ColumnsSlider(
              value: landscapeCols,
              onChanged: (value) => ref
                  .read(libraryLandscapeColumnsProvider.notifier)
                  .update(value),
            ),
          ] else ...[
            FilterSectionHeading(context.l10n.listSize),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: listScale,
                    min: 0.7,
                    max: 1.6,
                    divisions: 18,
                    label: '${(listScale * 100).round()}%',
                    onChanged: (value) => ref
                        .read(libraryListScaleProvider.notifier)
                        .update(double.parse(value.toStringAsFixed(2))),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${(listScale * 100).round()}%',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ColumnsSlider extends StatelessWidget {
  const _ColumnsSlider({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: value == 0 ? 'Auto' : '$value',
            onChanged: (next) => onChanged(next.round()),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(value == 0 ? 'Auto' : '$value', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
